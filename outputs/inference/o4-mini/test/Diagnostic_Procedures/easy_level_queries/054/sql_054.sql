WITH cohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
patient_admissions AS (
  SELECT
    c.subject_id,
    a.hadm_id
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.subject_id = a.subject_id
),
echocardiography_events AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pi.icd_code
  FROM
    patient_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      ON pa.subject_id = pi.subject_id
     AND pa.hadm_id    = pi.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pi.icd_code    = dp.icd_code
     AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%echocardi%'
),
adm_echo_counts AS (
  -- Count distinct echocardiography procedures per patient admission
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS echo_count
  FROM
    echocardiography_events
  GROUP BY
    subject_id,
    hadm_id
),
patient_max_echo AS (
  -- For each patient, take the maximum count across their admissions
  SELECT
    subject_id,
    MAX(echo_count) AS max_echo_count
  FROM
    adm_echo_counts
  GROUP BY
    subject_id
)
-- Finally, find the maximum across all patients in the cohort
SELECT
  MAX(max_echo_count) AS maximum_distinct_echos_per_patient
FROM
  patient_max_echo;