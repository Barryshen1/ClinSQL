WITH
-- Get male patients aged 67-77
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 67 AND 77
),

-- Get ADHF admissions (ICD-10 codes for acute decompensated heart failure)
adhd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM male_patients)
    AND d.icd_code IN (
      'I5021', 'I5022', 'I5023', 'I5031', 'I5032', 'I5033',
      'I5041', 'I5042', 'I5043', 'I509'
    )
    AND d.seq_num = 1  -- Primary diagnosis
),

-- Get ICU status on day 1
icu_day1_status AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    CASE WHEN TIMESTAMP_DIFF(i.intime, a.admittime, HOUR) <= 24 THEN 1 ELSE 0 END AS icu_day1
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    adhd_admissions a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Get CKD and diabetes prevalence
comorbidities AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM adhd_admissions)
  GROUP BY
    d.subject_id, d.hadm_id
)

-- Final aggregation
SELECT
  CASE WHEN a.los_days <= 7 THEN '≤7 days' ELSE '>7 days' END AS los_stratum,
  CASE WHEN i.icu_day1 = 1 THEN 'Yes' ELSE 'No' END AS icu_day1_status,
  COUNT(DISTINCT a.hadm_id) AS total_admissions,
  SUM(a.hospital_expire_flag) AS deaths,
  ROUND(100 * SUM(a.hospital_expire_flag) / COUNT(DISTINCT a.hadm_id), 2) AS mortality_rate,
  SUM(c.has_ckd) AS ckd_cases,
  ROUND(100 * SUM(c.has_ckd) / COUNT(DISTINCT a.hadm_id), 2) AS ckd_prevalence,
  SUM(c.has_diabetes) AS diabetes_cases,
  ROUND(100 * SUM(c.has_diabetes) / COUNT(DISTINCT a.hadm_id), 2) AS diabetes_prevalence
FROM
  adhd_admissions a
LEFT JOIN
  icu_day1_status i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
LEFT JOIN
  comorbidities c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
GROUP BY
  los_stratum, icu_day1_status
ORDER BY
  los_stratum, icu_day1_status;