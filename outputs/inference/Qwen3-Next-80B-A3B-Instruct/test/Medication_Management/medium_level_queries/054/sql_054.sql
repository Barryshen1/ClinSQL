WITH target_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di1
    ON p.subject_id = di1.subject_id AND a.hadm_id = di1.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di2
    ON p.subject_id = di2.subject_id AND a.hadm_id = di2.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      (d1.icd_version = 9 AND d1.icd_code LIKE '250%')
      OR (d1.icd_version = 10 AND d1.icd_code LIKE 'E10%')
      OR (d1.icd_version = 10 AND d1.icd_code LIKE 'E11%')
      OR (d1.icd_version = 10 AND d1.icd_code LIKE 'E13%')
      OR (d1.icd_version = 10 AND d1.icd_code LIKE 'E14%')
    )
    AND (
      (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
      OR (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),

glp1_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug_name
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE LOWER(drug) IN (
    'liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide',
    'albiglutide', 'tirzepatide', 'liraglutide injection', 'semaglutide injection',
    'exenatide injection', 'dulaglutide injection', 'lixisenatide injection'
  )
),

prescriptions_in_window AS (
  SELECT
    p.subject_id,
    p.starttime,
    CASE
      WHEN p.starttime >= c.admittime AND p.starttime <= c.admittime + INTERVAL '48' HOUR THEN 1
      ELSE 0
    END AS in_first_48h,
    CASE
      WHEN p.starttime >= c.dischtime - INTERVAL '24' HOUR AND p.starttime <= c.dischtime THEN 1
      ELSE 0
    END AS in_last_24h
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN target_cohort c
    ON p.subject_id = c.subject_id
  INNER JOIN glp1_drugs g
    ON LOWER(p.drug) = g.drug_name
  WHERE p.starttime IS NOT NULL
)

SELECT
  ROUND(100.0 * SUM(in_first_48h) / COUNT(*), 2) AS prevalence_first_48h_percent,
  ROUND(100.0 * SUM(in_last_24h) / COUNT(*), 2) AS prevalence_last_24h_percent,
  ROUND(100.0 * (SUM(in_last_24h) - SUM(in_first_48h)) / COUNT(*), 2) AS net_change_percent
FROM (
  SELECT
    subject_id,
    MAX(in_first_48h) AS in_first_48h,
    MAX(in_last_24h) AS in_last_24h
  FROM prescriptions_in_window
  GROUP BY subject_id
) AS patient_level;