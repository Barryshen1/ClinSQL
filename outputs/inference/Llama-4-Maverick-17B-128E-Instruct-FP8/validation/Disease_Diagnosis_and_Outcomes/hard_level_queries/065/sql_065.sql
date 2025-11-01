WITH patients_with_dvt AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 71 AND 81
  AND dicd.long_title LIKE '%deep vein thrombosis%'
),
charlson_score AS (
  SELECT subject_id, hadm_id, 
         SUM(CASE 
             WHEN icd_code IN ('410.0', '410.1', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 1  
             WHEN icd_code LIKE '428%' THEN 1  
             WHEN icd_code LIKE '4%' OR icd_code LIKE '5%' THEN 1  
             ELSE 0
             END) AS charlson_index
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
mortality_and_los AS (
  SELECT a.subject_id, a.hadm_id, 
         a.dischtime, p.dod,
         CASE WHEN p.dod IS NOT NULL AND p.dod <= (a.dischtime + INTERVAL 90 DAY) THEN 1 ELSE 0 END AS died_within_90_days,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
)
SELECT 
  APPROX_QUANTILES(charlson_index, 100)[OFFSET(50)] AS median_charlson_score,
  APPROX_QUANTILES(charlson_index, 100)[OFFSET(25)] AS q1_charlson_score,
  APPROX_QUANTILES(charlson_index, 100)[OFFSET(75)] AS q3_charlson_score,
  AVG(died_within_90_days) AS avg_90_day_mortality,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
FROM patients_with_dvt
INNER JOIN charlson_score USING (subject_id, hadm_id)
INNER JOIN mortality_and_los USING (subject_id, hadm_id);