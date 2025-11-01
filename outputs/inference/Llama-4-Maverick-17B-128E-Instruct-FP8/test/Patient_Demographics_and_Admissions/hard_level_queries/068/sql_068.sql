WITH admissions_filtered AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
  AND a.insurance = 'Medicare'
  AND a.admission_location = 'SKILLED NURSING FACILITY'
  AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 43 AND 53
),
dehydration_admissions AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE d.seq_num = 1  
  AND LOWER(di.long_title) LIKE '%dehydration%'  
)
SELECT COUNT(*)
FROM admissions_filtered
WHERE hadm_id IN (SELECT hadm_id FROM dehydration_admissions);