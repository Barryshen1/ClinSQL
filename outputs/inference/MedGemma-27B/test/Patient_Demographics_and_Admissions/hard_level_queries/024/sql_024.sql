WITH PatientCohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    p.gender,
    p.anchor_age,
    d_diag.long_title AS principal_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND d_diag.long_title LIKE '%ischemic stroke%'
), Readmission AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    a2.hadm_id AS readmission_hadm_id,
    a2.admittime AS readmission_admittime,
    a2.dischtime AS readmission_dischtime,
    a2.deathtime AS readmission_deathtime
  FROM PatientCohort AS pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON pc.subject_id = a2.subject_id
    AND a2.admittime > pc.dischtime
    AND a2.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
), IndexLOS AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS index_los
  FROM PatientCohort
), ReadmissionLOS AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS readmission_los
  FROM Readmission
)
SELECT
  COUNT(DISTINCT r.subject_id) AS num_readmitted,
  COUNT(DISTINCT pc.subject_id) AS total_patients,
  (COUNT(DISTINCT r.subject_id) / COUNT(DISTINCT pc.subject_id)) * 100 AS readmission_rate,
  AVG(CASE
    WHEN r;