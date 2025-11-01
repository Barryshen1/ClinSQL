WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 42
    AND gender = 'F'
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND di.seq_num = 1
    AND d.long_title LIKE '%hemorrhagic stroke%'
),
HospitalLOS AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM Admissions AS a
)
SELECT
  PERCENTILE_CONT(0.75, los) AS percentile_75_los
FROM HospitalLOS;