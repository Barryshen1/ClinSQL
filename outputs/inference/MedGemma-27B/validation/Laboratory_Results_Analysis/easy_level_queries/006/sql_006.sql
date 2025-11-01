WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 50
), DiagnosisInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code = 'J44.9' -- COPD code
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS sodium_value,
    l.valueuom AS sodium_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Sodium'
), PatientDiagnosis AS (
  SELECT DISTINCT
    p.subject_id
  FROM PatientInfo AS p
  INNER JOIN DiagnosisInfo AS d
    ON p.subject_id = d.subject_id
), PatientLabs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.sodium_value,
    l.sodium_uom
  FROM LabInfo AS l
  INNER JOIN PatientDiagnosis AS pd
    ON l.subject_id = pd.subject_id
)
SELECT
  STDDEV(sodium_value)
FROM PatientLabs;