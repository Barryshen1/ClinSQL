WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 69 AND 79
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.discharge_location,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE 'I2%' -- AMI codes
), ICUStayInfo AS (
  SELECT
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.first_careunit,
    s.last_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    AdmissionInfo AS a
    ON s.hadm_id = a.hadm_id
), ShockInfo AS (
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Shock Index')
    AND value > 1.0 -- Define shock index threshold
), RespiratoryFailureInfo AS (
  SELECT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Respiratory Rate')
    AND value > 30 -- Define respiratory failure threshold
), FinalData AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.discharge_location,
    a.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality,
    CASE
      WHEN a.los BETWEEN 1 AND 3 THEN '1-3'
      WHEN a.los BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group
  FROM
    AdmissionInfo AS a
  JOIN
    DiagnosisInfo AS d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN;