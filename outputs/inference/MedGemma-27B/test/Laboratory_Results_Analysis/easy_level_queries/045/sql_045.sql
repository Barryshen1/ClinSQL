WITH SepsisAdmissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND d.icd_code = 'R65.21' -- Sepsis code
),
CreatinineMeasurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
),
MalePatients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 83
)
SELECT
  MAX(cm.creatinine_value) AS max_creatinine
FROM SepsisAdmissions AS sa
JOIN MalePatients AS mp
  ON sa.subject_id = mp.subject_id
JOIN CreatinineMeasurements AS cm
  ON sa.subject_id = cm.subject_id AND sa.hadm_id = cm.hadm_id;