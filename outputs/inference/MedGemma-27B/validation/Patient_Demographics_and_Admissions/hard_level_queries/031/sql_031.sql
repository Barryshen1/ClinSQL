WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    -- Calculate approximate birth date based on anchor_year and anchor_age
    DATE(anchor_year - anchor_age, 1, 1) AS approx_birth_date
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag,
    a.insurance,
    d.long_title AS diagnosis_description,
    d.icd_version AS icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.hadm_id = di.hadm_id AND di.seq_num = 1 -- Principal diagnosis
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
)
SELECT
  COUNT(DISTINCT ai.hadm_id) AS total_index_admissions
FROM
  AdmissionInfo AS ai
  INNER JOIN PatientInfo AS pi
    ON ai.subject_id = pi.subject_id
WHERE
  pi.gender = 'F'
  AND pi.insurance = 'Medicare'
  AND pi.anchor_age BETWEEN 62 AND 72
  AND ai.admission_location = 'EMERGENCY'
  AND (
    (
      ai.icd_version = '9' AND ai.diagnosis_description LIKE 'Syncope%'
    ) OR (
      ai.icd_version = '10' AND ai.diagnosis_description LIKE 'Syncope%'
    )
  )
  AND (
    (
      ai.icd_version = '9' AND ai.diagnosis_description LIKE '780.2%'
    ) OR (
      ai.icd_version = '10' AND ai.diagnosis_description LIKE 'R55%'
    )
  );