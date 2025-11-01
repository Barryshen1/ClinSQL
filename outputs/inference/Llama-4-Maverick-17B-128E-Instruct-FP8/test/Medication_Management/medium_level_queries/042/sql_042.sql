WITH diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE d_icd.long_title LIKE '%Diabetes%' AND diag.icd_version = 10
),
hf_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
  ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE (d_icd.long_title LIKE '%Heart failure%' OR d_icd.long_title LIKE '%Cardiac failure%') AND diag.icd_version = 10
),
target_patients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61
  AND a.hadm_id IN (SELECT hadm_id FROM diabetes_patients) 
  AND a.hadm_id IN (SELECT hadm_id FROM hf_patients)
),
medication_usage AS (
  SELECT tp.subject_id, tp.hadm_id, tp.admittime, tp.dischtime,
         p.drug, p.starttime, p.stoptime
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON tp.hadm_id = p.hadm_id
  WHERE (LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%')
),
medication_category AS (
  SELECT subject_id, hadm_id, dischtime,
         CASE 
           WHEN COUNT(CASE WHEN LOWER(drug) LIKE '%insulin%' THEN 1 END) > 0 THEN 'Insulin'
           ELSE 'Oral Agents'
         END AS medication_type_first_48,
         CASE 
           WHEN COUNT(CASE WHEN LOWER(drug) LIKE '%insulin%' AND starttime <= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND (stoptime >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) OR stoptime IS NULL) THEN 1 END) > 0 THEN 'Insulin'
           ELSE 'Oral Agents'
         END AS medication_type_last_24
  FROM medication_usage
  GROUP BY subject_id, hadm_id, dischtime
),
medication_status_change AS (
  SELECT mc.subject_id, mc.hadm_id,
         mc.medication_type_first_48, mc.medication_type_last_24,
         CASE 
           WHEN mc.medication_type_first_48 = mc.medication_type_last_24 THEN 'Continued'
           WHEN mc.medication_type_first_48 IS NOT NULL AND mc.medication_type_last_24 IS NULL THEN 'Discontinued'
           WHEN mc.medication_type_first_48 IS NULL AND mc.medication_type_last_24 IS NOT NULL THEN 'Initiated'
           ELSE 'Changed'
         END AS medication_status_change
  FROM medication_category mc
)
SELECT 
  medication_type_first_48, 
  medication_status_change, 
  COUNT(*) AS count
FROM medication_status_change
GROUP BY medication_type_first_48, medication_status_change;