WITH 
  -- Filter patients by gender, age
  target_patients AS (
    SELECT subject_id, anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 79 AND 89
  ),
  
  -- Filter admissions by admission location, hadm_id existence in target_patients, insurance, and admission type
  target_admissions AS (
    SELECT a.hadm_id, a.admittime, a.admission_location, a.admission_type, a.insurance
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN target_patients tp ON a.subject_id = tp.subject_id
    WHERE a.admission_location = 'Emergency Department' 
      AND a.admission_type = 'Inpatient'
      AND a.insurance = 'Medicare'
  ),
  
  -- Filter diagnoses by principal diagnosis of pneumonia
  pneumonia_diagnoses AS (
    SELECT hadm_id, icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE seq_num = 1 AND icd_version = 'ICD-10' AND icd_code LIKE 'J18%'  -- ICD-10 code for pneumonia
  )

-- Count admissions with pneumonia diagnosis
SELECT COUNT(DISTINCT ta.hadm_id) AS total_admissions
FROM target_admissions ta
JOIN pneumonia_diagnoses pd ON ta.hadm_id = pd.hadm_id;