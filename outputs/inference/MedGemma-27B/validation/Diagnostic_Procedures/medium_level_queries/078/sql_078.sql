WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 88 AND 98
    AND gender = 'F'
), DiagnosisInfo AS (
  SELECT
    p.subject_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON d.subject_id = p.subject_id
  WHERE
    d.icd_code = 'I63' -- TIA code
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    a.admission_type,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.transfertime,
    a.curr_service,
    a.prev_service,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN DiagnosisInfo AS di
      ON a.subject_id = di.subject_id
    INNER JOIN PatientInfo AS pi
      ON a.subject_id = pi.subject_id
), ProcedureInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code,
    p.chartdate
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    INNER JOIN AdmissionInfo AS ai
      ON p.subject_id = ai.subject_id
      AND p.hadm_id = ai.hadm_id
  WHERE
    p.icd_code LIKE '7%' -- CT/MRI codes
), ICUInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.hadm_id = i.hadm_id
    INNER JOIN DiagnosisInfo AS di
      ON a.subject_id = di.subject_id
    INNER JOIN PatientInfo AS pi
      ON a.subject_id = pi.subject_id
), ProcedureCounts AS (
  SELECT
    ai.hadm_id,
    ai.subject_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital;