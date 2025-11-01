SELECT
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_icu_los_days
FROM (
  SELECT
    icu.stay_id,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND diag.icd_version = 10
    AND (
      diag.icd_code LIKE 'I60%'
      OR diag.icd_code LIKE 'I61%'
      OR diag.icd_code LIKE 'I63%'
      OR diag.icd_code LIKE 'I64%'
    )
);