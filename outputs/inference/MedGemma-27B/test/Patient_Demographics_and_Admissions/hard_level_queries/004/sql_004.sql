WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    admission_type,
    admission_location,
    insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), DiagnosisInfo AS (
  SELECT
    hadm_id,
    seq_num,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
), ICDCodes AS (
  SELECT
    icd_code,
    long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    icd_version = 9
)
SELECT
  COUNT(DISTINCT a.hadm_id)
FROM
  AdmissionInfo AS a
INNER JOIN
  PatientInfo AS p ON a.subject_id = p.subject_id
INNER JOIN
  DiagnosisInfo AS d ON a.hadm_id = d.hadm_id
INNER JOIN
  ICDCodes AS icd ON d.icd_code = icd.icd_code
WHERE
  p.gender = 'F'
  AND p.insurance = 'Medicare' -- Corrected column name and value
  AND p.anchor_age BETWEEN 85 AND 95
  AND a.admission_location = 'Transfer from another hospital'
  AND d.seq_num = 1
  AND icd.long_title LIKE '%osteomyelitis%';