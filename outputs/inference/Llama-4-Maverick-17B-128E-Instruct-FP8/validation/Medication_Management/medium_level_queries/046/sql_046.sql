WITH 
diabetes_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Diabetes mellitus type 2%' OR h.icd_code LIKE 'E11%'
),
heart_failure_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I50%'
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 63 AND 73
  AND a.hadm_id IN (SELECT hadm_id FROM diabetes_patients)
  AND a.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
  AND a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
),
medication_usage AS (
  SELECT e.hadm_id,
         MAX(CASE WHEN p.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR) THEN 
                  CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END 
             ELSE 0 END) AS insulin_first_24,
         MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_anytime,
         MAX(CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime THEN 
                  CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END 
             ELSE 0 END) AS insulin_last_24,
         MAX(CASE WHEN p.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR) THEN 
                  CASE WHEN LOWER(p.drug) NOT LIKE '%insulin%' AND 
                            (LOWER(p.drug) LIKE '%metformin%' OR 
                             LOWER(p.drug) LIKE '%glimepiride%' OR 
                             LOWER(p.drug) LIKE '%glyburide%' OR 
                             LOWER(p.drug) LIKE '%pioglitazone%' OR 
                             LOWER(p.drug) LIKE '%rosiglitazone%' OR 
                             LOWER(p.drug) LIKE '%sitagliptin%' OR 
                             LOWER(p.drug) LIKE '%saxagliptin%' OR 
                             LOWER(p.drug) LIKE '%linagliptin%' OR 
                             LOWER(p.drug) LIKE '%repaglinide%' OR 
                             LOWER(p.drug) LIKE '%nateglinide%') THEN 1 ELSE 0 END 
             ELSE 0 END) AS oral_first_24,
         MAX(CASE WHEN LOWER(p.drug) NOT LIKE '%insulin%' AND 
                       (LOWER(p.drug) LIKE '%metformin%' OR 
                        LOWER(p.drug) LIKE '%glimepiride%' OR 
                        LOWER(p.drug) LIKE '%glyburide%' OR 
                        LOWER(p.drug) LIKE '%pioglitazone%' OR 
                        LOWER(p.drug) LIKE '%rosiglitazone%' OR 
                        LOWER(p.drug) LIKE '%sitagliptin%' OR 
                        LOWER(p.drug) LIKE '%saxagliptin%' OR 
                        LOWER(p.drug) LIKE '%linagliptin%' OR 
                        LOWER(p.drug) LIKE '%repaglinide%' OR 
                        LOWER(p.drug) LIKE '%nateglinide%') THEN 1 ELSE 0 END) AS oral_anytime,
         MAX(CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 24 HOUR) AND e.dischtime THEN 
                  CASE WHEN LOWER(p.drug) NOT LIKE '%insulin%' AND 
                            (LOWER(p.drug) LIKE '%metformin%' OR 
                             LOWER(p.drug) LIKE '%glimepiride%' OR 
                             LOWER(p.drug) LIKE '%glyburide%' OR 
                             LOWER(p.drug) LIKE '%pioglitazone%' OR 
                             LOWER(p.drug) LIKE '%rosiglitazone%' OR 
                             LOWER(p.drug) LIKE '%sitagliptin%' OR 
                             LOWER(p.drug) LIKE '%saxagliptin%' OR 
                             LOWER(p.drug) LIKE '%linagliptin%' OR 
                             LOWER(p.drug) LIKE '%repaglinide%' OR 
                             LOWER(p.drug) LIKE '%nateglinide%') THEN 1 ELSE 0 END 
             ELSE 0 END) AS oral_last_24
  FROM eligible_patients e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON e.hadm_id = p.hadm_id
  GROUP BY e.hadm_id
)
SELECT 
  COUNT(CASE WHEN insulin_first_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS insulin_prevalence_first_24,
  COUNT(CASE WHEN insulin_last_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS insulin_prevalence_last_24,
  COUNT(CASE WHEN oral_first_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS oral_prevalence_first_24,
  COUNT(CASE WHEN oral_last_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100 AS oral_prevalence_last_24,
  (COUNT(CASE WHEN insulin_last_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100) - 
  (COUNT(CASE WHEN insulin_first_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100) AS insulin_net_change,
  (COUNT(CASE WHEN oral_last_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100) - 
  (COUNT(CASE WHEN oral_first_24 = 1 THEN hadm_id END) / COUNT(hadm_id) * 100) AS oral_net_change
FROM medication_usage;