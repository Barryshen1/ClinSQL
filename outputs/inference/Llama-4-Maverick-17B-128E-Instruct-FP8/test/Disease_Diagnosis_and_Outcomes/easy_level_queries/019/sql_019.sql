WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 67 AND 77
),
admissions_data AS (
  SELECT a.subject_id, a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),
sepsis_admissions AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code IN ('A41.9', 'R65.21', 'T81.12XA', 'T81.44XA') 
    AND d.seq_num = 1  
)
SELECT STDDEV(los_days) AS sd_los
FROM admissions_data
WHERE hadm_id IN (SELECT hadm_id FROM sepsis_admissions);