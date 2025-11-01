WITH copd_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON p.subject_id = diag.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age = 90
  AND d_diag.long_title LIKE '%Chronic obstructive pulmonary disease%'
),
creatinine_avg AS (
  SELECT cp.subject_id, AVG(le.valuenum) AS avg_creatinine
  FROM copd_patients cp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON cp.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON icu.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_le ON le.itemid = d_le.itemid
  WHERE d_le.label = 'Creatinine' AND le.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY cp.subject_id
)
SELECT STDDEV(avg_creatinine) AS std_dev_creatinine
FROM creatinine_avg;