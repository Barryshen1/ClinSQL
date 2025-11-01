WITH stroke_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 10 AND icd_code LIKE 'I6[0-2]%') OR
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
  )
),
copd_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 10 AND icd_code IN ('J440', 'J441')) OR
    (icd_version = 9 AND icd_code LIKE '4912%')
  )
),
both_cohort AS (
  SELECT s.hadm_id
  FROM stroke_cohort s
  INNER JOIN copd_cohort c ON s.hadm_id = c.hadm_id
)
SELECT
  APPROX_QUANTILES(sub.los, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(sub.los, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(sub.los, 4)[OFFSET(3)] - APPROX_QUANTILES(sub.los, 4)[OFFSET(1)] AS iqr
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN both_cohort b
    ON a.hadm_id = b.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.dischtime > a.admittime
) AS sub
WHERE sub.los > 0;