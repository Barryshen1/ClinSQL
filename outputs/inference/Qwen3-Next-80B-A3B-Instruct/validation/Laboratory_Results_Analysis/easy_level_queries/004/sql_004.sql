WITH sepsis_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.anchor_age = 76
    AND p.gender = 'F'
    AND LOWER(d_icd.long_title) LIKE '%sepsis%'
),
platelet_measurements AS (
  SELECT sp.subject_id, sp.hadm_id, le.valuenum
  FROM sepsis_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sp.hadm_id = le.hadm_id AND sp.subject_id = le.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%platelet%'
    AND le.charttime >= sp.admittime
    AND le.charttime < TIMESTAMP_ADD(sp.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
),
per_patient_averages AS (
  SELECT subject_id, hadm_id, AVG(valuenum) AS mean_platelet
  FROM platelet_measurements
  GROUP BY subject_id, hadm_id
)
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_platelet) AS median_platelet_count
FROM per_patient_averages;