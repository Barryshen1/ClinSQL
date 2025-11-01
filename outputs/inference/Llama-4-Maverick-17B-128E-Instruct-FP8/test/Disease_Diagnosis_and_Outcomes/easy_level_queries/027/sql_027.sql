WITH upper_gi_bleed_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE lower(long_title) LIKE '%gastrointestinal hemorrhage%' 
    OR lower(long_title) LIKE '%upper gi bleed%' 
    OR lower(long_title) LIKE '%gastric ulcer%' 
    OR lower(long_title) LIKE '%duodenal ulcer%'
),
primary_upper_gi_bleed_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN (
    SELECT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM upper_gi_bleed_icd_codes)
    AND seq_num = 1  -- Primary diagnosis
  ) d ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 49 AND 59
)
SELECT MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_length_of_stay
FROM primary_upper_gi_bleed_patients;