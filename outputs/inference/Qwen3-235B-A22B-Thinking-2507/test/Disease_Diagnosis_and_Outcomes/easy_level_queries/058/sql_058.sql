WITH cohort AS (
  SELECT
    adm.hadm_id,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  WHERE
    diag.seq_num = 1  -- Primary diagnosis
    AND pat.gender = 'F'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    -- Age 37-47 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 37 AND 47
    -- Hemorrhagic stroke ICD codes
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432'))
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
    )
)
SELECT
  PERCENTILE_CONT(los, 0.75) OVER () AS p75_los
FROM
  cohort
LIMIT 1;