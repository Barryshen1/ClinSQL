WITH cohort AS (
  -- Base cohort: Male, 85-95yo at ICU admission, ICU stays with acute respiratory failure (ICD-10 J96%)
  SELECT DISTINCT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id AND d.icd_version = '10' AND d.icd_code LIKE 'J96%'
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year BETWEEN 85 AND 95
         OR p.anchor_age BETWEEN 85 AND 95)
    AND i.los > 0
    AND i.outtime IS NOT NULL
),

vitals AS (
  -- First 24h PaO2 (min) and FiO2 (max) from chartevents (arterial blood gas and vent settings)
  SELECT 
    c.stay_id,
    MIN(CASE WHEN di.label LIKE '%PaO2%' AND di.category = 'blood gas' AND c.valueuom = 'mmHg' 
             THEN c.valuenum END) AS min_pao2,
    MAX(CASE WHEN di.abbreviation IN ('FiO2', 'FiO2 Set') OR di.label LIKE '%FiO2%'
             THEN CASE WHEN c.valueuom LIKE '%%' THEN c.valuenum / 100.0 ELSE c.valuenum END
        END) AS max_fio2  -- Normalize % to decimal if needed
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  INNER JOIN cohort coh
    ON c.subject_id = coh.subject_id 
    AND c.hadm_id = coh.hadm_id 
    AND c.stay_id = coh.stay_id
  WHERE c.charttime >= coh.intime 
    AND c.charttime <= TIMESTAMP_ADD(coh.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND (di.label LIKE '%PaO2%' OR di.label LIKE '%FiO2%')
  GROUP BY c.stay_id
),

scores AS (
  -- Compute scaled SOFA respiratory score (0-100) as instability proxy per stay
  SELECT 
    coh.stay_id,
    coh.los,
    coh.hospital_expire_flag,
    COALESCE(
      CASE 
        WHEN v.min_pao2 IS NULL THEN 0
        WHEN v.max_fio2 IS NULL THEN (v.min_pao2 / 0.21)  -- Assume room air FiO2=0.21
        ELSE SAFE_DIVIDE(v.min_pao2, v.max_fio2)
      END, 0
    ) AS pao2_fio2_ratio,
    -- SOFA respiratory score (0-4), scaled to 0-100 (25 per point)
    (COALESCE(
      CASE 
        WHEN v.min_pao2 IS NULL OR v.max_fio2 IS NULL THEN 0
        WHEN SAFE_DIVIDE(v.min_pao2, v.max_fio2) > 400 THEN 0
        WHEN SAFE_DIVIDE(v.min_pao2, v.max_fio2) >= 300 THEN 1
        WHEN SAFE_DIVIDE(v.min_pao2, v.max_fio2) >= 200 THEN 2
        WHEN SAFE_DIVIDE(v.min_pao2, v.max_fio2) >= 100 THEN 3
        ELSE 4
      END, 0
    ) * 25.0) AS instability_score
  FROM cohort coh
  LEFT JOIN vitals v
    ON coh.stay_id = v.stay_id
)

-- Part 1: Percentile rank for instability score of 85 (high instability)
SELECT 
  'Percentile Rank for Score 85' AS metric,
  ROUND(
    AVG(
      CASE WHEN instability_score >= 85 THEN 1.0 ELSE 0.0 END
    ) * 100, 2
  ) AS percentile
FROM scores

UNION ALL

-- Part 2: Avg ICU LOS for most unstable quartile (top 25% by score DESC)
SELECT 
  'Most Unstable Quartile' AS metric,
  'Avg ICU LOS (days)' AS sub_metric,
  ROUND(AVG(los), 2) AS value
FROM (
  SELECT *, NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM scores
)
WHERE instability_quartile = 1

UNION ALL

-- Part 3: In-hospital mortality for most unstable quartile
SELECT 
  'Most Unstable Quartile' AS metric,
  'In-Hospital Mortality Rate (%)' AS sub_metric,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS value
FROM (
  SELECT *, NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM scores
)
WHERE instability_quartile = 1;