WITH stroke_male_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.subject_id = diag.subject_id AND a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON diag.icd_code = ddi.icd_code AND diag.icd_version = ddi.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND LOWER(ddi.long_title) LIKE '%ischemic stroke%'
)

SELECT MIN(le.valuenum) AS min_hemoglobin_24h
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
JOIN stroke_male_admissions AS sma
  ON le.hadm_id = sma.hadm_id
  AND le.subject_id = sma.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
  ON le.itemid = dli.itemid
WHERE LOWER(dli.label) LIKE '%hemoglobin%'
  AND le.charttime BETWEEN sma.admittime AND TIMESTAMP_ADD(sma.admittime, INTERVAL 1 DAY)
  AND le.valuenum IS NOT NULL;