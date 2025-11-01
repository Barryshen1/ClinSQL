WITH ischemic_stroke_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE
    di.seq_num = 1
    AND (
      -- ICD-10: I63.*
      (di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^I63'))
      -- ICD-9: 433.x1 or 434.x1 (x = any digit)
      OR (di.icd_version = 9 AND (
        REGEXP_CONTAINS(di.icd_code, r'^433[0-9]1$')
        OR REGEXP_CONTAINS(di.icd_code, r'^434[0-9]1$')
      ))
    )
)

SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN ischemic_stroke_admissions isa
      ON a.subject_id = isa.subject_id AND a.hadm_id = isa.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
);