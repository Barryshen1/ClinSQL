WITH cohort AS (
  -- Get all admissions for men aged 75–85
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diagnosis_flags AS (
  -- For each admission, flag if it has ischemic heart disease/ACS and COPD
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MAX(CASE
      WHEN
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^41[0-4]')) -- ICD-9 410-414
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I2[0-5]')) -- ICD-10 I20-I25
      THEN 1 ELSE 0 END) AS has_ihd_acs,
    MAX(CASE
      WHEN
        (d.icd_version = 9 AND d.icd_code = '496') -- ICD-9 496
        OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J44')) -- ICD-10 J44
      THEN 1 ELSE 0 END) AS has_copd
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
),
los_cohort AS (
  -- Only admissions with both conditions
  SELECT
    subject_id,
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    diagnosis_flags
  WHERE
    has_ihd_acs = 1
    AND has_copd = 1
    AND dischtime > admittime
)

SELECT
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_75th_percentile_days
FROM
  los_cohort
;