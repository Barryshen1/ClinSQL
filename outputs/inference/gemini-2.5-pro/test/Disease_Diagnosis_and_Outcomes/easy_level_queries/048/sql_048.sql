WITH SepsisAdmissions AS (
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    -- 1. Filter for female patients aged 67-77
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    -- 2. Filter for primary diagnoses (seq_num = 1 is the principal diagnosis)
    AND dx.seq_num = 1
    -- 3. Filter for sepsis or septic shock diagnoses by title
    AND (
      LOWER(d_dx.long_title) LIKE '%sepsis%'
      OR LOWER(d_dx.long_title) LIKE '%septic shock%'
    )
)
-- 4. Calculate the maximum LOS from the filtered admissions
SELECT
  MAX(TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY)) AS max_hospital_los_days
FROM
  SepsisAdmissions AS sa;