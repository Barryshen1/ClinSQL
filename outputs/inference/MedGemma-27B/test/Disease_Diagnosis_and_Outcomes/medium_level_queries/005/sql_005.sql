WITH PatientHF AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND p.anchor_age IS NOT NULL
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientHF
    )
),
ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    AdmissionInfo AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.icustays` AS i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
ComorbidityCount AS (
  SELECT
    a.subject_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN (
      'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.9', 'I11.0', 'I11.9', 'I10', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.2', 'I15.0', 'I15.1', 'I15.2', 'I15.9', 'I11.0', 'I11.9', 'I10', 'I12.0', 'I12.9', 'I13.0', 'I13.1', 'I13.2', 'I15.0', 'I15.1', 'I15.2', 'I15.9', 'I25.1', 'I25.8', 'I25.9', 'I20.0', 'I20.1', 'I20.2', 'I20.3', 'I20.4', 'I20.5', 'I20.6', 'I20.8', 'I20.9', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9', 'I23.0', 'I23.1', 'I23.2', 'I23.3', 'I23.4', 'I23.5', 'I23.6', 'I23.7', 'I23.8', 'I23.9', 'I24.0', 'I24.1', 'I24.2', 'I24.3', 'I24.4', 'I24.5', 'I24.6', 'I24.7', 'I24.8', 'I24.9', 'I25.1', 'I25.8', 'I25.9', 'I20.0', 'I20.1', 'I20.2', 'I20.3', 'I20.4', ';