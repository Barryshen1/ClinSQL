WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 64
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis_description
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
    AND d.long_title LIKE '%Ischemic Stroke%'
),
AgeGroupInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 59 AND 69
),
FinalInfo AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN AgeGroupInfo AS agi
    ON a.subject_id = agi.subject_id
  JOIN AdmissionInfo AS ai
    ON a.hadm_id = ai.hadm_id
)
SELECT
  MEDIAN(DATE_DIFF(dischtime, admitime, DAY)) AS median_los
FROM FinalInfo;