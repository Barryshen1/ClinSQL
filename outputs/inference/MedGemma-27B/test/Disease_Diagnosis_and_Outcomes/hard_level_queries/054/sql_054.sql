WITH
  PE_Patients AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      d.long_title AS diagnosis,
      -- Placeholder for comorbidity score calculation
      -- Replace with actual comorbidity score calculation based on ICD codes
      0 AS comorbidity_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
      JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON a.hadm_id = di.hadm_id
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
      AND d.long_title LIKE '%pulmonary embolism%'
      AND a.admission_type = 'EMERGENCY'
      AND a.hospital_expire_flag = 0
  ),
  GeneralInpatientCohort AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      -- Placeholder for comorbidity score calculation
      -- Replace with actual comorbidity score calculation based on ICD codes
      0 AS comorbidity_score
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
      AND a.admission_type = 'EMERGENCY'
      AND a.hospital_expire_flag = 0
  )
SELECT
  -- Calculate metrics for PE_Patients cohort
  AVG(PE_Patients.comorbidity_score) AS mean_comorbidity_score_pe,
  AVG(CASE WHEN PE_Patients.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_pe,
  -- Add calculations for complication rates and survivor LOS for PE patients
  -- Add calculations for complication rates and survivor LOS for GeneralInpatientCohort
  -- Add matched profile percentile calculation
FROM
  PE_Patients;