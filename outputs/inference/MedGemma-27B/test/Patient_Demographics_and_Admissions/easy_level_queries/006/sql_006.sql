WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), ICDInfo AS (
  SELECT
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code LIKE '001%'
), ICUInfo AS (
  SELECT
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  PERCENTILE_CONT(0.5, ICUInfo.los) AS median_icu_los
FROM
  ICUInfo
INNER JOIN
  AdmissionInfo ON ICUInfo.hadm_id = AdmissionInfo.hadm_id
INNER JOIN
  PatientInfo ON AdmissionInfo.subject_id = PatientInfo.subject_id
INNER JOIN
  ICDInfo ON AdmissionInfo.hadm_id = ICDInfo.hadm_id
WHERE
  PatientInfo.gender = 'F' AND PatientInfo.anchor_age BETWEEN 58 AND 68
GROUP BY
  ICUInfo.hadm_id;