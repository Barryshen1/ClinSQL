WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
valve_procedures AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 10 AND icd_code LIKE '02%'  -- Simplified filter for ICD-10 valve procedures
  OR icd_version = 9 AND (icd_code LIKE '35.1%' OR icd_code LIKE '35.2%')  -- Simplified filter for ICD-9 valve procedures
),
relevant_patients AS (
  SELECT pa.subject_id
  FROM patient_admissions pa
  WHERE pa.age_at_admission BETWEEN 42 AND 52
  AND pa.hadm_id IN (SELECT hadm_id FROM valve_procedures)
),
procedure_counts AS (
  SELECT rp.subject_id, COUNT(DISTINCT vp.hadm_id) AS num_procedures
  FROM relevant_patients rp
  JOIN valve_procedures vp ON rp.subject_id = vp.subject_id
  GROUP BY rp.subject_id
)

SELECT AVG(num_procedures) AS avg_procedures_per_patient
FROM procedure_counts;