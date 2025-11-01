WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%diabetes%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
),
MedicationInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.medication,
    p.drug_type,
    p.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND p.medication LIKE '%insulin%'
    AND p.drug_type = 'insulin'
),
OralMedicationInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.medication,
    p.drug_type,
    p.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND p.medication NOT LIKE '%insulin%'
    AND p.drug_type = 'oral'
),
TimeWindows AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS los_hours
  FROM
    AdmissionInfo
),
InsulinCounts AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    COUNT(DISTINCT m.subject_id) AS insulin_count
  FROM
    TimeWindows AS t
  JOIN
    MedicationInfo AS m
    ON t.subject_id = m.subject_id
    AND t.hadm_id = m.hadm_id
    AND m.starttime BETWEEN t.admittime AND TIMESTAMP_ADD(t.admittime, INTERVAL 48 HOUR)
  GROUP;