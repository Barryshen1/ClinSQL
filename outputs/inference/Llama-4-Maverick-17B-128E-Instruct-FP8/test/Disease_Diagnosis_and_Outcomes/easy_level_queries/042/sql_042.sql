WITH relevant_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 78 AND 88
  AND ((d.icd_version = 9 AND d.icd_code BETWEEN '410' AND '414') 
       OR (d.icd_version = 10 AND dicd.icd_code LIKE 'I2%'))
  AND d.seq_num = 1  -- Primary diagnosis
),
hospital_los AS (
  SELECT a.hadm_id, DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN relevant_admissions ra ON a.hadm_id = ra.hadm_id
)
SELECT AVG(los) AS avg_hospital_los
FROM hospital_los;