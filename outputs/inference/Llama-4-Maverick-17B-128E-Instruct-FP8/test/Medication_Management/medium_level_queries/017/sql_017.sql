WITH 
-- Define patients with diabetes and heart failure
diabetes_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Diabetes%' AND h.icd_version = 10
),
heart_failure_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Heart failure%' AND h.icd_version = 10
),

-- Define female patients aged 37-47 with diabetes and heart failure
target_patients AS (
  SELECT p.subject_id, p.gender, ic.stay_id, ic.hadm_id, 
         ic.intime, ic.outtime,  -- Include intime and outtime
         TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ic.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 37 AND 47
  AND ic.subject_id IN (SELECT subject_id FROM diabetes_patients)
  AND ic.subject_id IN (SELECT subject_id FROM heart_failure_patients)
  AND TIMESTAMP_DIFF(ic.outtime, ic.intime, HOUR) >= 144
),

-- Medication use in first and last 72 hours
medication_use AS (
  SELECT tp.subject_id, tp.stay_id, p.drug,
         CASE 
           WHEN p.starttime <= tp.intime + INTERVAL 72 HOUR THEN 'first_72'
           ELSE 'last_72'
         END AS period
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON tp.hadm_id = p.hadm_id
  WHERE (p.starttime <= tp.intime + INTERVAL 72 HOUR OR 
         p.starttime >= tp.outtime - INTERVAL 72 HOUR)
),

medication_status AS (
  SELECT m1.subject_id, m1.stay_id, m1.drug,
         CASE 
           WHEN m1.period = 'first_72' AND m2.period = 'last_72' THEN 'continued'
           WHEN m1.period = 'first_72' AND m2.period IS NULL THEN 'discontinued'
           WHEN m1.period = 'last_72' AND m2.period IS NULL THEN 'initiated'
         END AS status
  FROM medication_use m1
  LEFT JOIN medication_use m2 ON m1.subject_id = m2.subject_id AND m1.stay_id = m2.stay_id AND m1.drug = m2.drug AND m2.period = 'last_72'
  WHERE m1.period = 'first_72'
  UNION ALL
  SELECT m2.subject_id, m2.stay_id, m2.drug, 'initiated' AS status
  FROM medication_use m2
  WHERE m2.period = 'last_72' AND CONCAT(m2.subject_id, m2.stay_id, m2.drug) NOT IN (SELECT CONCAT(subject_id, stay_id, drug) FROM medication_use WHERE period = 'first_72')
)

SELECT drug, status, COUNT(*) AS count
FROM medication_status
GROUP BY drug, status;