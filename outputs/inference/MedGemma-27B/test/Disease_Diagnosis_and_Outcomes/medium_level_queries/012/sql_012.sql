WITH PatientCohort AS (
  -- Select patients meeting the criteria: women, age 83-93, heart failure diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    d.icd_code,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND d.icd_code LIKE 'I50%' -- Heart failure codes (ICD-10)
    AND d.icd_version = '10'
),
AdmissionStats AS (
  -- Calculate LOS and mortality for each admission
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    -- Calculate LOS in days
    (TIMESTAMP_DIFF(dischtime, admitime, DAY) + 1) AS los,
    -- Calculate mortality flag
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality
  FROM PatientCohort
),
ICUStayStats AS (
  -- Calculate LOS for each ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    -- Calculate ICU LOS in days
    (TIMESTAMP_DIFF(outtime, intime, DAY) + 1) AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN PatientCohort AS pc
    ON i.subject_id = pc.subject_id AND i.hadm_id = pc.hadm_id
),
ComorbidityBurden AS (
  -- Calculate comorbidity burden for each patient
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    subject_id IN (SELECT subject_id FROM PatientCohort)
    AND icd_code NOT LIKE 'I50%' -- Exclude heart failure from comorbidity count
    AND icd_code NOT LIKE 'Z%' -- Exclude Z codes (factors influencing health status)
    AND icd_code NOT LIKE 'E%' -- Exclude E codes (external causes)
    AND icd_code NOT LIKE 'V%' -- Exclude V codes (factors influencing health status)
    AND icd_code NOT LIKE 'W%' -- Exclude W codes (external causes)
    AND icd_;