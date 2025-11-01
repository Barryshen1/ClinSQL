SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS percentile_25
FROM (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
    AND a.subject_id = diag.subject_id
  WHERE
    diag.seq_num = 1  -- Primary diagnosis
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '491.21')  -- ICD-9
      OR (diag.icd_version = 10 AND diag.icd_code = 'J44.1')  -- ICD-10
    )
    AND p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 49 AND 59
);