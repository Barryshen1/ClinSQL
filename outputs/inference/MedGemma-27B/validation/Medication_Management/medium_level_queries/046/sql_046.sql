WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_version = '9'
), PatientDiagnosisT2DM AS (
  SELECT
    subject_id
  FROM
    PatientDiagnosis
  WHERE
    icd_code = '250.00'
), PatientDiagnosisHF AS (
  SELECT
    subject_id
  FROM
    PatientDiagnosis
  WHERE
    icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.9')
), PatientDiagnosisT2DMHF AS (
  SELECT
    subject_id
  FROM
    PatientDiagnosisT2DM
  INTERSECT
  SELECT
    subject_id
  FROM
    PatientDiagnosisHF
), AdmissionMedication AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.medication,
    p.route,
    p.starttime,
    p.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    p.drug_type = 'Insulin' OR p.drug_type = 'Oral Agent'
), First24hMedication AS (
  SELECT
    subject_id,
    hadm_id,
    medication,
    route,
    starttime,
    stoptime
  FROM
    AdmissionMedication
  WHERE
    starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR)
), Final24hMedication AS (
  SELECT
    subject_id,
    hadm_id,
    medication,
    route,
    starttime,
    stoptime
  FROM
    AdmissionMedication
  WHERE
    starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime
), First24hMedicationCount AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS first24h_med_count
  FROM
    First24hMedication
  GROUP BY
    subject_id,
    hadm_id
), Final24hMedicationCount AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS final24h_med_count
  FROM
    Final24hMedication
  GROUP BY
    subject_id,
    hadm_id
), MedicationChange AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.first24h_med_count,
    fi.final24h_med_count,
    fi.final24h_med_count - f.first24h_med_count AS net_change
  FROM
    First24hMedicationCount AS f
  INNER JOIN
    Final24hMedicationCount AS fi
    ON f.subject_id = fi.subject_id AND f.hadm_id = fi.hadm_id
), PatientCohort AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    PatientDiagnosisT2DMHF
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON PatientDiagnosisT2DMHF.subject_id = a.subject_id
  WHERE
    a.gender = 'M' AND a.anchor_age BETWEEN 63 AND 73
), FinalCohortMedication AS (
  SELECT
    pc.subject_id,
    pc.hadm_;