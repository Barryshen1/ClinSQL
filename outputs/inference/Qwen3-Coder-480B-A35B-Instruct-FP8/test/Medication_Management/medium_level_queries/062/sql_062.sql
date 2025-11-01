WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd1
    ON d1.icd_code = d_icd1.icd_code AND d1.icd_version = d_icd1.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd2
    ON d2.icd_code = d_icd2.icd_code AND d2.icd_version = d_icd2.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      LOWER(d_icd1.long_title) LIKE '%diabetes%'
      OR d_icd1.icd_code IN ('E10', 'E11', 'E13', 'O24')
    )
    AND (
      LOWER(d_icd2.long_title) LIKE '%heart failure%'
      OR d_icd2.icd_code LIKE 'I50%'
    )
),

glp1_admins AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    e.charttime,
    CASE
      WHEN e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1
      ELSE 0
    END AS in_first_72h,
    CASE
      WHEN e.charttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 72 HOUR) AND c.outtime THEN 1
      ELSE 0
    END AS in_last_72h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
  WHERE
    LOWER(e.medication) IN (
      'semaglutide',
      'liraglutide',
      'dulaglutide',
      'exenatide'
    )
),

patient_flags AS (
  SELECT
    subject_id,
    MAX(in_first_72h) AS first_72h_flag,
    MAX(in_last_72h) AS last_72h_flag
  FROM
    glp1_admins
  GROUP BY
    subject_id
),

summary AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(first_72h_flag) AS first_72h_count,
    SUM(last_72h_flag) AS last_72h_count
  FROM
    patient_flags
)

SELECT
  total_patients,
  first_72h_count,
  last_72h_count,
  ROUND(SAFE_DIVIDE(first_72h_count, total_patients), 4) AS first_72h_rate,
  ROUND(SAFE_DIVIDE(last_72h_count, total_patients), 4) AS last_72h_rate,
  ROUND(SAFE_DIVIDE(last_72h_count, total_patients) - SAFE_DIVIDE(first_72h_count, total_patients), 4) AS abs_change,
  ROUND(SAFE_DIVIDE(
    SAFE_DIVIDE(last_72h_count, total_patients) - SAFE_DIVIDE(first_72h_count, total_patients),
    SAFE_DIVIDE(first_72h_count, total_patients)
  ), 4) AS rel_change
FROM
  summary;