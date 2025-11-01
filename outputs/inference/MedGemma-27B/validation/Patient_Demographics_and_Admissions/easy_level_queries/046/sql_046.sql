WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 42 -- Specific patient ID
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (
      SELECT
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        subject_id = 42
    )
), DAPT_Medications AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.subject_id = 42
    AND p.drug LIKE '%aspirin%'
    AND p.drug LIKE '%clopidogrel%'
    AND p.starttime >= (
      SELECT
        admittime
      FROM
        AdmissionInfo
      WHERE
        subject_id = 42
    )
    AND p.stoptime <= (
      SELECT
        dischtime
      FROM
        AdmissionInfo
      WHERE
        subject_id = 42
    )
), Cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    PatientInfo AS p
  JOIN
    AdmissionInfo AS a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.hadm_id IN (
      SELECT
        hadm_id
      FROM
        DAPT_Medications
    )
)
SELECT
  STDDEV(hospital_expire_flag)
FROM
  Cohort;