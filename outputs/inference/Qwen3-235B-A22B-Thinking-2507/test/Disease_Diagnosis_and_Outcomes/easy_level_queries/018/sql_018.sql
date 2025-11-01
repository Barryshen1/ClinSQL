WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    -- Primary diagnosis (seq_num = 1)
    diag.seq_num = 1
    -- Hemorrhagic stroke ICD codes
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430', '431'))
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%'))
    )
    -- Male patients
    AND pat.gender = 'M'
    -- Age 45-55 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 45 AND 55
    -- Exclude ongoing admissions
    AND adm.dischtime IS NOT NULL
)
SELECT
  STDDEV(los_days) AS sd_hospital_los
FROM filtered_admissions;