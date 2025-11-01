WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 93
    AND gender = 'F'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    d.long_title AS admission_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
    AND d.seq_num = 1
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND a.admission_type = 'EMERGENCY'
    AND d.icd_code LIKE 'J18%' -- Community-acquired pneumonia
), HospitalLOS AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los_days
  FROM
    AdmissionInfo
)
SELECT
  MIN(los_days) AS min_hospital_los
FROM
  HospitalLOS;