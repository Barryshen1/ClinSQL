WITH admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.gender,
    p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
primary_diagnosis AS (
  SELECT
    hadm_id,
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    seq_num = 1
)
SELECT
  PERCENTILE_CONT(los_days, 0.25) OVER() AS los_25th_percentile
FROM
  admissions_with_age a
JOIN
  primary_diagnosis d
ON
  a.hadm_id = d.hadm_id
WHERE
  a.gender = 'M'
  AND a.age_at_admission BETWEEN 73 AND 83
  AND (
    REGEXP_CONTAINS(d.icd_code, r'^E10\.1[01]') OR  -- DKA, Type 1
    REGEXP_CONTAINS(d.icd_code, r'^E11\.1[01]') OR  -- DKA, Type 2
    REGEXP_CONTAINS(d.icd_code, r'^E10\.0[01]') OR  -- HHS, Type 1
    REGEXP_CONTAINS(d.icd_code, r'^E11\.0[01]')     -- HHS, Type 2
  )
LIMIT 1;