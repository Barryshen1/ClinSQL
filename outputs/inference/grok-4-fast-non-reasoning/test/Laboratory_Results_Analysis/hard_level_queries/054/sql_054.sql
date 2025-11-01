WITH ami_cohort AS (
  -- Identify primary AMI admissions for females aged 38-48
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.seq_num = 1  -- Primary diagnosis
    AND (
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^410')) OR
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^I21'))
    )
    AND a.hadm_id IS NOT NULL
),

controls AS (
  -- Age-matched females without AMI
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^410')) OR
          (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^I21'))
        )
    )
),

lab_unstable AS (
  -- Unstable labs within 72 hours (for both cohorts)
  SELECT 
    l.subject_id,
    l.hadm_id,
    COUNT(*) AS instability_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN (
    SELECT hadm_id, admittime FROM ami_cohort
    UNION ALL
    SELECT hadm_id, admittime FROM controls
  ) adm ON l.hadm_id = adm.hadm_id
  WHERE l.charttime BETWEEN TIMESTAMP(adm.admittime) AND TIMESTAMP_ADD(TIMESTAMP(adm.admittime), INTERVAL 3 DAY)
    AND l.valuenum IS NOT NULL
    AND l.itemid IN (50863, 5125, 5123, 50912, 50971)  -- Troponin I, Troponin T, CKMB, Creatinine, Potassium (MIMIC-IV IDs)
    AND (
      -- Instability: outside ref range or extreme values
      (l.valuenum < COALESCE(l.ref_range_lower, 0) OR l.valuenum > COALESCE(l.ref_range_upper, 999))
      OR 
      -- Specific thresholds (fallback if ref range missing)
      (
        (l.itemid IN (50863, 5125) AND l.valuenum > 0.4)  -- Troponin >0.4 ng/mL
        OR (l.itemid = 50912 AND l.valuenum > 2.0)  -- Creatinine >2.0 mg/dL
        OR (l.itemid = 50971 AND (l.valuenum < 3.0 OR l.valuenum > 5.5))  -- K <3 or >5.5 mEq/L
        OR (l.itemid = 5123 AND l.valuenum > 10.0)  -- CKMB >10 ng/mL
      )
    )
  GROUP BY l.subject_id, l.hadm_id
),

ami_with_score AS (
  SELECT 
    ac.*,
    COALESCE(lu.instability_count, 0) AS instability_score,
    DATE_DIFF(DATE(ac.dischtime), DATE(ac.admittime), DAY) AS los_days,
    ac.hospital_expire_flag AS mortality
  FROM ami_cohort ac
  LEFT JOIN lab_unstable lu
    ON ac.subject_id = lu.subject_id AND ac.hadm_id = lu.hadm_id
),

control_critical_rate AS (
  SELECT 
    ROUND(AVG(CAST(COALESCE(lu.instability_count, 0) > 0 AS FLOAT64)), 4) AS critical_lab_rate,
    COUNT(DISTINCT c.hadm_id) AS n_controls
  FROM controls c
  LEFT JOIN lab_unstable lu
    ON c.subject_id = lu.subject_id AND c.hadm_id = lu.hadm_id
),

ami_quartiles AS (
  SELECT 
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    los_days,
    mortality
  FROM ami_with_score
),

quartile_stats AS (
  SELECT 
    quartile,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(CAST(mortality AS FLOAT64)), 4) AS mortality_rate,
    COUNT(*) AS n_patients,
    ROUND(AVG(CAST(instability_score > 0 AS FLOAT64)), 4) AS ami_critical_lab_rate
  FROM ami_quartiles
  GROUP BY quartile
)

-- Main results: Quartile outcomes for AMI + overall critical lab rates
SELECT 
  'AMI Quartile' AS group_type,
  quartile,
  avg_los_days,
  mortality_rate,
  n_patients,
  ami_critical_lab_rate
FROM quartile_stats

UNION ALL

SELECT 
  'AMI Overall' AS group_type,
  NULL AS quartile,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(CAST(mortality AS FLOAT64)), 4) AS mortality_rate,
  COUNT(*) AS n_patients,
  ROUND(AVG(CAST(instability_score > 0 AS FLOAT64)), 4) AS ami_critical_lab_rate
FROM ami_with_score

UNION ALL

SELECT 
  'Controls' AS group_type,
  NULL AS quartile,
  NULL AS avg_los_days,
  NULL AS mortality_rate,
  n_controls AS n_patients,
  critical_lab_rate AS control_critical_lab_rate
FROM control_critical_rate

ORDER BY group_type, quartile;