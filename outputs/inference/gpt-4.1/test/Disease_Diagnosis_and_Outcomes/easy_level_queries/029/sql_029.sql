WITH cohort AS (
  -- Find admissions for women aged 69-79
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
    AND p.anchor_age BETWEEN 69 AND 79
),
ugib_admissions AS (
  -- Admissions with UGIB diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      -- ICD-9 UGIB
      (icd_version = 9 AND (
        icd_code LIKE '578%' OR
        icd_code LIKE '531%' OR
        icd_code LIKE '532%' OR
        icd_code LIKE '533%' OR
        icd_code LIKE '534%'
      ))
      OR
      -- ICD-10 UGIB
      (icd_version = 10 AND (
        icd_code LIKE 'K92%' OR
        icd_code LIKE 'K25%' OR
        icd_code LIKE 'K26%' OR
        icd_code LIKE 'K27%' OR
        icd_code LIKE 'K28%'
      ))
    )
),
copd_exac_admissions AS (
  -- Admissions with COPD exacerbation diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      -- ICD-9 COPD exacerbation
      (icd_version = 9 AND (
        icd_code = '49121'
      ))
      OR
      -- ICD-10 COPD exacerbation
      (icd_version = 10 AND (
        icd_code = 'J441'
      ))
    )
),
final_cohort AS (
  -- Admissions with both UGIB and COPD exacerbation
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    INNER JOIN ugib_admissions u ON c.hadm_id = u.hadm_id
    INNER JOIN copd_exac_admissions copd ON c.hadm_id = copd.hadm_id
  WHERE
    c.admittime IS NOT NULL
    AND c.dischtime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(DATETIME_DIFF(dischtime, admittime, DAY), 2)[OFFSET(1)] AS median_los_days
FROM
  final_cohort;