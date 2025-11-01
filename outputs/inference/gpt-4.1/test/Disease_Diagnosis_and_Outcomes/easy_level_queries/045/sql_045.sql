WITH cohort AS (
  -- Get all admissions for women aged 77-87
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diagnoses AS (
  -- Get diagnoses for heart failure and COPD
  SELECT
    hadm_id,
    MAX(CASE
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
      THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE
      WHEN (icd_version = 9 AND icd_code = '496') OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J44'))
      THEN 1 ELSE 0 END) AS has_copd
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
final_cohort AS (
  -- Admissions with both heart failure and COPD
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM
    cohort c
    JOIN diagnoses d ON c.hadm_id = d.hadm_id
  WHERE
    d.has_hf = 1
    AND d.has_copd = 1
    AND DATETIME_DIFF(c.dischtime, c.admittime, DAY) >= 0
)
SELECT
  STDDEV_POP(los_days) AS sd_hospital_los_days
FROM
  final_cohort
;