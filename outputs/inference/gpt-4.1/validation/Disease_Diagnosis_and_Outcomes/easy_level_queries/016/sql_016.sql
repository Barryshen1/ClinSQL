WITH cohort AS (
  -- Get admissions for males aged 68-78
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diagnoses AS (
  -- Get all diagnoses for qualifying admissions
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN cohort c
      ON d.subject_id = c.subject_id
      AND d.hadm_id = c.hadm_id
),
pneumonia_hadm AS (
  -- Admissions with pneumonia
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE
    -- ICD-10 J12–J18 or ICD-9 480–486
    (icd_version = 10 AND (LEFT(icd_code, 3) BETWEEN 'J12' AND 'J18'))
    OR (icd_version = 9 AND (LEFT(icd_code, 3) BETWEEN '480' AND '486'))
),
copd_hadm AS (
  -- Admissions with COPD
  SELECT DISTINCT hadm_id
  FROM diagnoses
  WHERE
    -- ICD-10 J44 or ICD-9 496
    (icd_version = 10 AND LEFT(icd_code, 3) = 'J44')
    OR (icd_version = 9 AND LEFT(icd_code, 3) = '496')
),
final_cohort AS (
  -- Admissions with BOTH pneumonia AND COPD
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    INNER JOIN pneumonia_hadm pn
      ON c.hadm_id = pn.hadm_id
    INNER JOIN copd_hadm cp
      ON c.hadm_id = cp.hadm_id
)
SELECT
  PERCENTILE_CONT(
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0, 0.75
  ) OVER () AS los_75th_percentile_days
FROM
  final_cohort
;