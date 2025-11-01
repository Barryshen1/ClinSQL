WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),

aki_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN patients_filtered p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute kidney injury%'
     OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),

drug_exposure AS (
  SELECT 
    p.hadm_id,
    MAX(CASE 
      WHEN LOWER(p.drug) IN (
        'midazolam', 'lorazepam', 'diazepam', 'propofol', 'fentanyl', 'morphine', 
        'oxycodone', 'clonazepam', 'alprazolam', 'phenobarbital', 'dexmedetomidine'
      ) THEN 1 ELSE 0 
    END) AS has_cns,
    MAX(CASE 
      WHEN LOWER(p.drug) IN (
        'vancomycin', 'gentamicin', 'tobramycin', 'amikacin', 'amphotericin', 
        'cisplatin', 'cyclosporine', 'tacrolimus', 'ibuprofen', 'ketorolac', 
        'naproxen', 'contrast', 'radiocontrast'
      ) THEN 1 ELSE 0 
    END) AS has_nephro
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  JOIN aki_admissions aki ON p.hadm_id = aki.hadm_id
  WHERE p.drug IS NOT NULL
  GROUP BY p.hadm_id
),

admission_groups AS (
  SELECT 
    aki.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(de.has_cns, 0) AS has_cns,
    COALESCE(de.has_nephro, 0) AS has_nephro,
    CASE 
      WHEN COALESCE(de.has_cns, 0) = 1 AND COALESCE(de.has_nephro, 0) = 1 THEN 'both'
      ELSE 'other'
    END AS drug_group
  FROM aki_admissions aki
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON aki.hadm_id = a.hadm_id
  LEFT JOIN drug_exposure de ON aki.hadm_id = de.hadm_id
),

complexity_los AS (
  SELECT
    ag.hadm_id,
    ag.drug_group,
    ag.hospital_expire_flag,
    -- Medication complexity: number of distinct drugs
    COALESCE(p_count.drug_count, 0) AS complexity,
    -- LOS in days
    DATETIME_DIFF(ag.dischtime, ag.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM admission_groups ag
  LEFT JOIN (
    SELECT hadm_id, COUNT(DISTINCT LOWER(drug)) AS drug_count
    FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
    WHERE drug IS NOT NULL
    GROUP BY hadm_id
  ) p_count ON ag.hadm_id = p_count.hadm_id
),

group_stats AS (
  SELECT
    drug_group,
    -- Complexity quartiles
    APPROX_QUANTILES(complexity, 100)[OFFSET(25)] AS q1_complexity,
    APPROX_QUANTILES(complexity, 100)[OFFSET(50)] AS median_complexity,
    APPROX_QUANTILES(complexity, 100)[OFFSET(75)] AS q3_complexity,
    AVG(complexity) AS mean_complexity,
    -- Mean LOS
    AVG(los_days) AS mean_los_days,
    -- Overall mortality
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    -- Top-quartile LOS threshold
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_q3
  FROM complexity_los
  GROUP BY drug_group
),

-- Now compute mortality in top-quartile LOS patients
top_los_mortality AS (
  SELECT
    cl.drug_group,
    AVG(CAST(cl.hospital_expire_flag AS FLOAT64)) AS top_quartile_mortality
  FROM complexity_los cl
  JOIN group_stats gs ON cl.drug_group = gs.drug_group
  WHERE cl.los_days >= gs.los_q3
  GROUP BY cl.drug_group
)

-- Final output
SELECT
  gs.drug_group,
  gs.q1_complexity,
  gs.median_complexity,
  gs.q3_complexity,
  gs.mean_complexity,
  gs.mean_los_days,
  gs.mortality_rate,
  gs.los_q3 AS top_quartile_los_threshold,
  COALESCE(tlm.top_quartile_mortality, 0) AS top_quartile_mortality
FROM group_stats gs
LEFT JOIN top_los_mortality tlm ON gs.drug_group = tlm.drug_group
ORDER BY gs.drug_group;