WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.seq_num = 1 -- Primary diagnosis
), ICDCodes AS (
  SELECT
    di.icd_code,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
  WHERE
    di.icd_version = 'ICD9CM'
), PneumoniaCodes AS (
  SELECT
    ic.icd_code
  FROM
    ICDCodes AS ic
  WHERE
    ic.long_title LIKE '%Pneumonia%'
    AND ic.long_title LIKE '%Community-Acquired%'
), HospitalStay AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
  FROM
    AdmissionInfo AS a
  WHERE
    a.admission_type = 'EMERGENCY' -- Assuming community-acquired pneumonia usually presents as emergency
    AND a.admission_location = 'EMERGENCY ROOM' -- Assuming community-acquired pneumonia usually presents from ER
)
SELECT
  PERCENTILE_CONT(0.25, hs.length_of_stay) AS percentile_25_los
FROM
  HospitalStay AS hs
JOIN
  PatientInfo AS pi ON hs.subject_id = pi.subject_id
JOIN
  DiagnosisInfo AS di ON hs.hadm_id = di.hadm_id
JOIN
  PneumoniaCodes AS pc ON di.icd_code = pc.icd_code
WHERE
  pi.gender = 'F'
  AND pi.anchor_age BETWEEN 67 AND 77;