WITH sepsis_male_hadm AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
    ON dcode.icd_code = diag.icd_code
   AND dcode.icd_version = diag.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = a.subject_id
  WHERE LOWER(pat.gender) = 'male'
    AND LOWER(dcode.long_title) LIKE '%sepsis%'
)

SELECT
  -- 75th percentile of platelet count on discharge day
  APPROX_QUANTILES(le.valuenum, 101)[OFFSET(75)] AS platelet_p75
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN sepsis_male_hadm AS s ON s.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  ON le.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
  ON li.itemid = le.itemid
WHERE LOWER(li.label) LIKE '%platelet%'
  AND DATE(le.charttime) = DATE(a.dischtime)
  AND le.valuenum IS NOT NULL;