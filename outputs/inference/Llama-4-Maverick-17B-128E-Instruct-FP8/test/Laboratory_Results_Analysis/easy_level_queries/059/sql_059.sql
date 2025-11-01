WITH sepsis_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE lower(long_title) LIKE '%sepsis%' AND icd_version = 10
),
sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M' AND d.icd_code IN (SELECT icd_code FROM sepsis_icd_codes) AND a.dischtime IS NOT NULL
),
platelet_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE lower(label) LIKE '%platelet count%'
),
discharge_day_platelet AS (
  SELECT l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN sepsis_admissions s ON l.hadm_id = s.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM platelet_itemid)
  AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT PERCENTILE_CONT(valuenum, 0.75) OVER () AS percentile_75_platelet_count
FROM discharge_day_platelet
LIMIT 1;