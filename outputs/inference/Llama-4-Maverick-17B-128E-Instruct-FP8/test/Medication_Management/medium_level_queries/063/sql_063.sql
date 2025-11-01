WITH diabetic_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Diabetes%' AND d.icd_version = 10
),
heart_failure_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Heart failure%' AND d.icd_version = 10
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 45 AND 55
  AND a.hadm_id IN (SELECT hadm_id FROM diabetic_patients) AND a.hadm_id IN (SELECT hadm_id FROM heart_failure_patients)
),
medication_analysis AS (
  SELECT ep.hadm_id,
         COUNT(DISTINCT CASE WHEN p.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 12 HOUR) AND LOWER(p.drug) LIKE '%insulin%' THEN p.drug END) AS first_12_hours_insulin,
         COUNT(DISTINCT CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 72 HOUR) AND ep.dischtime AND LOWER(p.drug) LIKE '%insulin%' THEN p.drug END) AS last_72_hours_insulin,
         COUNT(DISTINCT CASE WHEN p.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 12 HOUR) AND (LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%') THEN p.drug END) AS first_12_hours_oral,
         COUNT(DISTINCT CASE WHEN p.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 72 HOUR) AND ep.dischtime AND (LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%') THEN p.drug END) AS last_72_hours_oral
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON ep.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%'
  GROUP BY ep.hadm_id
)
SELECT 
  IF(COUNT(hadm_id) = 0, NULL, COUNT(CASE WHEN first_12_hours_insulin > 0 THEN hadm_id END) / COUNT(hadm_id)) AS first_12_hours_insulin_rate,
  IF(COUNT(hadm_id) = 0, NULL, COUNT(CASE WHEN last_72_hours_insulin > 0 THEN hadm_id END) / COUNT(hadm_id)) AS last_72_hours_insulin_rate,
  IF(COUNT(hadm_id) = 0, NULL, COUNT(CASE WHEN first_12_hours_oral > 0 THEN hadm_id END) / COUNT(hadm_id)) AS first_12_hours_oral_rate,
  IF(COUNT(hadm_id) = 0, NULL, COUNT(CASE WHEN last_72_hours_oral > 0 THEN hadm_id END) / COUNT(hadm_id)) AS last_72_hours_oral_rate,
  IF(COUNT(hadm_id) = 0, NULL, (COUNT(CASE WHEN first_12_hours_insulin > 0 THEN hadm_id END) / COUNT(hadm_id)) - (COUNT(CASE WHEN last_72_hours_insulin > 0 THEN hadm_id END) / COUNT(hadm_id))) AS insulin_pp_diff,
  IF(COUNT(hadm_id) = 0, NULL, (COUNT(CASE WHEN first_12_hours_oral > 0 THEN hadm_id END) / COUNT(hadm_id)) - (COUNT(CASE WHEN last_72_hours_oral > 0 THEN hadm_id END) / COUNT(hadm_id))) AS oral_pp_diff
FROM medication_analysis;