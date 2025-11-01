WITH 
patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
                       WHERE lower(long_title) LIKE '%diabetes%')
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
                       WHERE lower(long_title) LIKE '%heart failure%')
  )
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime,
         TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR) AS first_24h_end,
         TIMESTAMP_SUB(i.outtime, INTERVAL 24 HOUR) AS last_24h_start
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_filtered p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),
prescriptions_analysis AS (
  SELECT i.stay_id, 
         MAX(CASE WHEN p.starttime BETWEEN i.intime AND i.first_24h_end AND lower(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_first_24h,
         MAX(CASE WHEN p.starttime BETWEEN i.intime AND i.first_24h_end AND lower(p.drug) NOT LIKE '%insulin%' AND p.drug_type = 'RX' THEN 1 ELSE 0 END) AS oral_agent_first_24h,
         MAX(CASE WHEN p.starttime BETWEEN i.last_24h_start AND i.outtime AND lower(p.drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_last_24h,
         MAX(CASE WHEN p.starttime BETWEEN i.last_24h_start AND i.outtime AND lower(p.drug) NOT LIKE '%insulin%' AND p.drug_type = 'RX' THEN 1 ELSE 0 END) AS oral_agent_last_24h
  FROM icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
  GROUP BY i.stay_id
)
SELECT 
  COUNT(CASE WHEN insulin_first_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100 AS insulin_initiation_rate_first_24h,
  COUNT(CASE WHEN oral_agent_first_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100 AS oral_agent_initiation_rate_first_24h,
  COUNT(CASE WHEN insulin_last_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100 AS insulin_initiation_rate_last_24h,
  COUNT(CASE WHEN oral_agent_last_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100 AS oral_agent_initiation_rate_last_24h,
  (COUNT(CASE WHEN insulin_last_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100) - (COUNT(CASE WHEN insulin_first_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100) AS insulin_absolute_diff,
  (COUNT(CASE WHEN oral_agent_last_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100) - (COUNT(CASE WHEN oral_agent_first_24h = 1 THEN stay_id END) / COUNT(stay_id) * 100) AS oral_agent_absolute_diff
FROM prescriptions_analysis;