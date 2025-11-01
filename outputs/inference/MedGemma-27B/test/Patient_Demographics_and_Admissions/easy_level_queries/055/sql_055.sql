WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 54
),
DiagnosisInfo AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  JOIN PatientInfo AS p
    ON d.subject_id = p.subject_id
  WHERE
    icd.long_title LIKE '%pneumonia%'
),
AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN DiagnosisInfo AS di
    ON a.subject_id = di.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, DATE_DIFF(dischtime, admittime, DAY)) AS percentile_25_los
FROM AdmissionInfo
WHERE
  dischtime IS NOT NULL
  AND admittime IS NOT NULL;