WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS adm_year,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
),

pancreatitis_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'K85%' AND d.icd_version = 10
),

diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  GROUP BY hadm_id
),

-- Define major complications by ICD-10 codes
complication_codes AS (
  SELECT 'J96.0' AS icd_code, 1 AS version UNION ALL
  SELECT 'N17', 1 UNION ALL
  SELECT 'A41.9', 1 UNION ALL
  SELECT 'R65.20', 1 UNION ALL
  SELECT 'R57.9', 1 UNION ALL
  SELECT 'K86.3', 1 UNION ALL
  SELECT 'K85.2', 1
),

complication_flags AS (
  SELECT
    di.hadm_id,
    1 AS complication_present
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN complication_codes cc
    ON di.icd_code = cc.icd_code AND di.icd_version = cc.version
  GROUP BY di.hadm_id
),

admission_risks AS (
  SELECT
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    COALESCE(dc.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(COUNT(cf.complication_present), 0) AS complication_count
  FROM pancreatitis_admissions pa
  LEFT JOIN diagnosis_counts dc ON pa.hadm_id = dc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  LEFT JOIN complication_codes cc
    ON di.icd_code = cc.icd_code AND di.icd_version = cc.version
  LEFT JOIN complication_flags cf ON pa.hadm_id = cf.hadm_id
  GROUP BY pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, dc.diagnosis_count
),

risk_scores AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    diagnosis_count,
    complication_count,
    (diagnosis_count + 5 * complication_count) AS risk_score,
    (DATETIME_DIFF(dischtime, admittime, SECOND) / (60 * 60 * 24.0)) AS los_days
  FROM admission_risks
  WHERE dischtime IS NOT NULL
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM risk_scores
),

quartile_stats AS (
  SELECT
    risk_quartile,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CASE WHEN complication_count > 0 THEN 1.0 ELSE 0.0 END) AS complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[OFFSET(50)] AS median_survivor_los
  FROM quartiles
  GROUP BY risk_quartile

  UNION ALL

  SELECT
    0 AS risk_quartile,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CASE WHEN complication_count > 0 THEN 1.0 ELSE 0.0 END) AS complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[OFFSET(50)] AS median_survivor_los
  FROM quartiles
)

SELECT
  CASE
    WHEN risk_quartile = 1 THEN 'Q1 (Lowest Risk)'
    WHEN risk_quartile = 2 THEN 'Q2'
    WHEN risk_quartile = 3 THEN 'Q3'
    WHEN risk_quartile = 4 THEN 'Q4 (Highest Risk)'
    ELSE 'Overall'
  END AS risk_group,
  ROUND(mortality_rate, 3) AS in_hospital_mortality,
  ROUND(complication_rate, 3) AS major_complication_rate,
  ROUND(median_survivor_los, 2) AS median_survivor_los_days
FROM quartile_stats
ORDER BY risk_quartile;