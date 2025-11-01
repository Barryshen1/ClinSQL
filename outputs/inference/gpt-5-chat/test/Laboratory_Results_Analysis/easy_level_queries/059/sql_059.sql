WITH sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddd
    ON diag.icd_code = ddd.icd_code
   AND diag.icd_version = ddd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 93
    AND LOWER(ddd.long_title) LIKE '%sepsis%'
)
SELECT
  PERCENTILE_CONT(le.valuenum, 0.75) OVER() AS platelet_75th_percentile
FROM sepsis_admissions AS sa
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON sa.hadm_id = le.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
  ON le.itemid = di.itemid
WHERE le.valuenum IS NOT NULL
  AND LOWER(di.label) LIKE '%platelet%'
  AND DATE(le.charttime) = DATE(sa.dischtime);