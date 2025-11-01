WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 82
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN AdmissionInfo AS a
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    d.icd_code = 'I63' -- Ischemic stroke code
), GlucoseEvents AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS glucose_value,
    le.valueuom AS glucose_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  JOIN DiagnosisInfo AS diag
    ON le.subject_id = diag.subject_id AND le.hadm_id = diag.hadm_id
  WHERE
    dli.label = 'Glucose' AND le.valueuom = 'mg/dL'
)
SELECT
  PERCENTILE_CONT(0.75, glucose_value) AS percentile_75
FROM GlucoseEvents;