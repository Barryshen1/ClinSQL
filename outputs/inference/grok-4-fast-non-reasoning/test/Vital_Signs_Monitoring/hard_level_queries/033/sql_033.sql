WITH cohort AS (
  -- Base cohort: females aged 51-61 with ICU stays
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    i.outtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

first_stay AS (
  -- First ICU stay per subject (edge: multiple stays)
  SELECT *
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM cohort
  )
  WHERE rn = 1
),

sofa_components AS (
  -- Extract relevant chartevents in first 48h for SOFA (common itemids; extend as needed)
  SELECT 
    fs.subject_id,
    fs.stay_id,
    fs.intime,
    fs.los,
    fs.hospital_expire_flag,
    -- Respiratory (PaO2/FiO2; assume FiO2=1 if missing for vent patients)
    SAFE_DIVIDE(
      MIN(CASE WHEN c.itemid = 220277 THEN c.valuenum END),  -- PaO2 (min for worst)
      COALESCE(MAX(CASE WHEN c.itemid = 223835 THEN c.valuenum END), 1.0)  -- FiO2 (max for worst ratio)
    ) AS pao2_fio2,
    -- Cardio (MAP)
    MIN(CASE WHEN c.itemid = 220052 THEN c.valuenum END) AS map,
    -- Hepatic (Bilirubin, mg/dL)
    MAX(CASE WHEN c.itemid = 50883 THEN c.valuenum END) AS bilirubin,
    -- Renal (Creatinine, mg/dL)
    MAX(CASE WHEN c.itemid = 50912 THEN c.valuenum END) AS creatinine,
    -- Coagulation (Platelets, 10^3/uL)
    MIN(CASE WHEN c.itemid = 51265 THEN c.valuenum END) AS platelets,
    -- Neuro (GCS; min total for worst)
    (MIN(CASE WHEN c.itemid = 220739 THEN c.valuenum END) +  -- GCS Eye
     MIN(CASE WHEN c.itemid = 223900 THEN c.valuenum END) +  -- GCS Verbal
     MIN(CASE WHEN c.itemid = 223901 THEN c.valuenum END)) AS gcs  -- GCS Motor
  FROM first_stay fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON fs.stay_id = c.stay_id
  WHERE c.charttime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
    AND c.itemid IN (220277, 223835, 220052, 50883, 50912, 51265, 220739, 223900, 223901)
  GROUP BY fs.subject_id, fs.stay_id, fs.intime, fs.los, fs.hospital_expire_flag
  HAVING COUNT(DISTINCT c.itemid) >= 4  -- Require sufficient data for valid SOFA
),

sofa_scores AS (
  -- Calculate SOFA subscores (worst values) and total scaled to 0-100
  SELECT 
    subject_id,
    stay_id,
    -- Respiratory SOFA (0-4)
    CASE 
      WHEN pao2_fio2 >= 400 THEN 0
      WHEN pao2_fio2 >= 300 THEN 1
      WHEN pao2_fio2 >= 200 THEN 2
      WHEN pao2_fio2 >= 100 THEN 3
      ELSE 4
    END AS sofa_resp,
    -- Cardio SOFA (0-4; simplified, assumes no vaso)
    CASE 
      WHEN map >= 70 THEN 0
      WHEN map >= 60 THEN 1
      ELSE 4  -- >4 assumes severe
    END AS sofa_cardio,
    -- Hepatic (0-4)
    CASE 
      WHEN bilirubin < 1.2 THEN 0
      WHEN bilirubin < 2.0 THEN 1
      WHEN bilirubin < 6.0 THEN 2
      WHEN bilirubin < 12.0 THEN 3
      ELSE 4
    END AS sofa_hepatic,
    -- Renal (0-4)
    CASE 
      WHEN creatinine < 1.2 THEN 0
      WHEN creatinine < 2.0 THEN 1
      WHEN creatinine < 3.0 THEN 2
      WHEN creatinine < 4.0 THEN 3
      ELSE 4
    END AS sofa_renal,
    -- Coagulation (0-4; invert platelets)
    CASE 
      WHEN platelets >= 150 THEN 0
      WHEN platelets >= 100 THEN 1
      WHEN platelets >= 50 THEN 2
      WHEN platelets >= 20 THEN 3
      ELSE 4
    END AS sofa_coag,
    -- Neuro (0-4; invert GCS)
    CASE 
      WHEN gcs >= 15 THEN 0
      WHEN gcs >= 13 THEN 1
      WHEN gcs >= 10 THEN 2
      WHEN gcs >= 6 THEN 3
      ELSE 4
    END AS sofa_neuro,
    los,
    hospital_expire_flag
  FROM sofa_components
),

final_scores AS (
  SELECT 
    *,
    (sofa_resp + sofa_cardio + sofa_hepatic + sofa_renal + sofa_coag + sofa_neuro) * (100.0 / 24.0) AS instability_score
  FROM sofa_scores
)

-- Part 1: Percentile of instability score 80
SELECT 
  'Percentile of instability score 80' AS metric,
  ROUND(PERCENTILE_CONT(80, ARRAY_AGG(instability_score ORDER BY instability_score)) * 100, 2) AS percentile
FROM final_scores

UNION ALL

-- Part 2: ICU LOS and mortality for most unstable decile (top 10%)
SELECT 
  'Most unstable decile - Mean ICU LOS (days)' AS metric,
  ROUND(AVG(los), 2) AS value
FROM (
  SELECT los,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM final_scores
)
WHERE decile = 1  -- Top decile

UNION ALL

SELECT 
  'Most unstable decile - Mortality rate' AS metric,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS value_pct
FROM (
  SELECT hospital_expire_flag,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM final_scores
)
WHERE decile = 1;