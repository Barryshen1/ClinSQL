WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.edouttime,
    a.deathtime,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'PHYSICIAN REFERRAL'
    AND a.discharge_location = 'HOME'
    AND a.insurance = 'Medicare'
    AND a.language = 'ENGL'
    AND a.marital_status = 'MARRIED'
    AND a.race = 'WHITE'
    AND a.edregtime BETWEEN '2195-01-01 00:00:00' AND '2195-01-01 00:00:00'
    AND a.edouttime BETWEEN '2195-01-01 00:00:00' AND '2195-01-01 00:00:00'
    AND a.deathtime BETWEEN '2195-01-01 00:00:00' AND '2195-01-01 00:00:00'
    AND a.los BETWEEN 0 AND 1000000000
  ),
  ICUStay AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      i.los
    FROM PatientCohort AS a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.subject_id = i.subject_id
      AND a.hadm_id = i.hadm_id
  ),
  AMI AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      d.icd_code
    FROM PatientCohort AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    WHERE
      d.icd_code = 'I21.9'
  ),
  RiskScore AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.charttime,
      a.value AS risk_score
    FROM PatientCohort AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
      ON a.subject_id = e.subject_id
      AND a.hadm_id = e.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ed
      ON e.emar_id = ed.emar_id
      AND e.emar_seq = ed.emar_seq
    WHERE
      ed.field_name = 'Risk Score'
      AND ed.field_value = 'High'
  ),
  Mortality AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.deathtime
    FROM PatientCohort AS a
    WHERE
      a.deathtime IS NOT NULL
  ),
  Complication AS (
    SELECT
      a.subject_id,
      a.;