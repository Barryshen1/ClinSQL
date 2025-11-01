WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag,
    d.long_title AS diagnosis_title,
    d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'ED'
    AND d.long_title LIKE '%UTI%'
), Readmission AS (
  SELECT
    pc.subject_id,
    pc.admittime AS index_admittime,
    pc.dischtime AS index_dischtime,
    pc.deathtime AS index_deathtime,
    a.admittime AS readmit_admittime,
    a.dischtime AS readmit_dischtime,
    a.deathtime AS readmit_deathtime,
    a.hospital_expire_flag AS readmit_expire_flag
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.subject_id = a.subject_id
  WHERE
    a.admittime > pc.dischtime
    AND a.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
), ReadmissionStatus AS (
  SELECT
    subject_id,
    index_admittime,
    index_dischtime,
    index_deathtime,
    readmit_admittime,
    readmit_dischtime,
    readmit_deathtime,
    readmit_expire_flag,
    CASE
      WHEN readmit_admittime IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted
  FROM Readmission
)
SELECT
  AVG(readmitted) AS readmission_rate,
  AVG(CASE WHEN readmitted = 1 THEN TIMESTAMP_DIFF(readmit_dischtime, index_dischtime, DAY) ELSE NULL END) AS median_los_readmitted,
  AVG(CASE WHEN readmitted = 0 THEN TIMESTAMP_DIFF(index_dischtime, index_dischtime, DAY) ELSE NULL END) AS median_los_non_readmitted,
  AVG(CASE WHEN readmitted = 1 AND TIMESTAMP_DIFF(readmit_dischtime, index_dischtime, DAY) > 9 THEN 1 ELSE 0 END) AS percent_los_greater_than_9_days
FROM ReadmissionStatus;