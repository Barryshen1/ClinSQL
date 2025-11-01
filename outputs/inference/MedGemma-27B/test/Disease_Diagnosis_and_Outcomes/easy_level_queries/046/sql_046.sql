WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 48
), DiagnosisInfo AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53 AND icd.long_title LIKE '%hemorrhagic stroke%' AND d.seq_num = 1
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime - a.admittime AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hospital_expire_flag = 0
), CombinedInfo AS (
  SELECT
    DISTINCT
    a.subject_id,
    a.hadm_id,
    a.los_days
  FROM AdmissionInfo AS a
  JOIN DiagnosisInfo AS d
    ON a.subject_id = d.subject_id
)
SELECT
  STDDEV(los_days)
FROM CombinedInfo;