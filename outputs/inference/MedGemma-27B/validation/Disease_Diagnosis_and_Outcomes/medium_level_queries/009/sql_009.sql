WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 53-63, sepsis (excluding septic shock)
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hospital_expire_flag = 1 -- Assuming sepsis is indicated by mortality, need to refine this
),
SepsisDiagnosis AS (
  -- Identify patients with sepsis diagnosis (ICD-9 code 995.92 or ICD-10 code R65.21)
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    d.icd_code IN ('995.92', 'R65.21')
    AND d.icd_version = 9 -- Assuming ICD-9 for 995.92
),
SepticShockDiagnosis AS (
  -- Identify patients with septic shock diagnosis (ICD-9 code 995.93 or ICD-10 code R65.22)
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    d.icd_code IN ('995.93', 'R65.22')
    AND d.icd_version = 9 -- Assuming ICD-9 for 995.93
),
ICUStays AS (
  -- Select ICU stays for the identified patients
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  INNER JOIN PatientCohort AS pc
    ON s.subject_id = pc.subject_id AND s.hadm_id = pc.hadm_id
  WHERE
    s.stay_id IN (
      SELECT
        stay_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        stay_;