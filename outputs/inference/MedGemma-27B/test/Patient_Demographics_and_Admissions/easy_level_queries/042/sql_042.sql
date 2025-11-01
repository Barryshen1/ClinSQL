WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age = 79
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND p.icd_code = '42801' -- CABG ICD-10 code
), ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM AdmissionInfo AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
)
SELECT
  AVG(los) AS mean_icu_los
FROM ICUStayInfo
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM PatientInfo
  );