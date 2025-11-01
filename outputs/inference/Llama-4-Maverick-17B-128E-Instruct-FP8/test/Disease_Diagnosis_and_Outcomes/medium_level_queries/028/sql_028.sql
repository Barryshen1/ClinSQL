WITH hf_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, 
         a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
  AND dicd.long_title LIKE '%Heart failure%'
),
comorbidity_burden AS (
  SELECT subject_id, hadm_id, 
         SUM(CASE 
           WHEN icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 1
           WHEN icd_code LIKE '428%' THEN 1
           -- Add more conditions as needed for Charlson Comorbidity Index
           ELSE 0
         END) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
los_data AS (
  SELECT a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
los_quartiles AS (
  SELECT hadm_id, los,
         NTILE(4) OVER (ORDER BY los) AS los_quartile
  FROM los_data
),
mortality_data AS (
  SELECT hf.subject_id, hf.hadm_id, hf.hospital_expire_flag,
         cb.comorbidity_score,
         lq.los_quartile
  FROM hf_patients hf
  JOIN comorbidity_burden cb ON hf.hadm_id = cb.hadm_id
  JOIN los_quartiles lq ON hf.hadm_id = lq.hadm_id
)
SELECT 
  los_quartile,
  CASE 
    WHEN comorbidity_score = 0 THEN 'low'
    WHEN comorbidity_score BETWEEN 1 AND 2 THEN 'medium'
    ELSE 'high'
  END AS comorbidity_burden,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality
FROM mortality_data
GROUP BY los_quartile, 
         CASE 
           WHEN comorbidity_score = 0 THEN 'low'
           WHEN comorbidity_score BETWEEN 1 AND 2 THEN 'medium'
           ELSE 'high'
         END
ORDER BY los_quartile, comorbidity_burden;