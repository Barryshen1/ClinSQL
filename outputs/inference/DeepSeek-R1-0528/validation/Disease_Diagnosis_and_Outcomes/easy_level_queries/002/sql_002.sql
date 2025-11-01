WITH cohort AS (
  SELECT
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%')  -- ICD-9 AKI
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')  -- ICD-10 AKI
    )
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 52 AND 62  -- Age 52-62 at admission
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los
FROM cohort;