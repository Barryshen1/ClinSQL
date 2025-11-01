WITH sepsis_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 58 AND 68
    AND LOWER(d.long_title) LIKE '%sepsis%'
)
SELECT
  APPROX_QUANTILES(icu.los, 100)[OFFSET(50)] AS median_icu_los_days
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN
  sepsis_admissions sa
  ON icu.hadm_id = sa.hadm_id
  AND icu.subject_id = sa.subject_id;