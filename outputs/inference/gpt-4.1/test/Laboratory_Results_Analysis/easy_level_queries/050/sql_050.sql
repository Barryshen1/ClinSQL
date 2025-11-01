WITH sepsis_admissions AS (
  SELECT DISTINCT adm.hadm_id, adm.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND (
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '99591'
        OR diag.icd_code LIKE '99592'
        OR diag.icd_code LIKE '78552'
        OR diag.icd_code LIKE '038%'
      ))
      OR
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'A40%'
        OR diag.icd_code LIKE 'A41%'
      ))
    )
)
, first_platelet AS (
  SELECT
    sa.hadm_id,
    le.valuenum AS platelet_count
  FROM sepsis_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE dlab.label = 'PLATELET'
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY sa.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  STDDEV_SAMP(platelet_count) AS admission_platelet_stddev
FROM first_platelet;