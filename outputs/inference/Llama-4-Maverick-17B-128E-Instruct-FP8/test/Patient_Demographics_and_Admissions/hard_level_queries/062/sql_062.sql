WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),
acute_cholecystitis_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%acute cholecystitis%'
    AND di.seq_num = 1
)
SELECT COUNT(*)
FROM eligible_patients
INNER JOIN acute_cholecystitis_admissions USING (hadm_id);