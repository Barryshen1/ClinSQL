WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 84 AND 94
),
stroke_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM patient_filter)
  AND d.seq_num = 1  
  AND ((d.icd_version = 9 AND d.icd_code IN ('433.01', '433.11', '433.21', '433.31', '433.81', '433.91', '434.01', '434.11', '434.91'))
  OR (d.icd_version = 10 AND d.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE lower(long_title) LIKE '%cerebral infarction%')))
),
los AS (
  SELECT hadm_id, DATETIME_DIFF(dischtime, admittime, DAY) AS hospital_los
  FROM stroke_admissions
)
SELECT MAX(hospital_los) AS max_hospital_los
FROM los;