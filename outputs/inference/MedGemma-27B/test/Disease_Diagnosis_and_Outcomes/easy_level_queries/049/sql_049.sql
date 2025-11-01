WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 55
),
AdmissionsInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientInfo)
    AND di.icd_code LIKE 'I63%'
),
HospitalLOS AS (
  SELECT
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM
    AdmissionsInfo
)
SELECT
  PERCENTILE_CONT(los, 0.25) AS percentile_25
FROM
  HospitalLOS;