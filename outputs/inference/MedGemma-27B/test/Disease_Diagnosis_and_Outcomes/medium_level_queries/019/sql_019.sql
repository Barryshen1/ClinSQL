WITH PatientHF AS (
  -- Identify patients with heart failure (HF) diagnosis
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 58
    AND d.icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
    AND d.icd_version = 10
),
PatientAgeGroup AS (
  -- Filter patients within the specified age range (53-63)
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
),
PatientHFAndAge AS (
  -- Combine HF and age group criteria
  SELECT
    p.subject_id
  FROM PatientHF AS hf
  JOIN PatientAgeGroup AS age
    ON hf.subject_id = age.subject_id
),
AdmissionInfo AS (
  -- Get admission details and calculate Charlson Comorbidity Index (CCI)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.disch_location,
    a.los,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.hospital_expire_flag,
    a.deathtime,
    a.dischtime,
    a.disch_location,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.hospital_expire_flag,
    a.deathtime,
    a.dischtime,
    a.disch_location,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.hospital_expire_flag,
    a.deathtime,
    a.dischtime,
    a.disch_location,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.hospital_expire_flag,
    a.;