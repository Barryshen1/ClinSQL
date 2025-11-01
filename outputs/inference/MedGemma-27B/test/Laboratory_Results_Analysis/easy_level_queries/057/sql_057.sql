WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 61
    AND gender = 'M'
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code
  WHERE
    diag.icd_code LIKE 'J18%' -- Pneumonia ICD-10 codes
),
CreatinineMeasurements AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.charttime,
    a.valuenum AS creatinine_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS b ON a.itemid = b.itemid
  WHERE
    b.label = 'Creatinine'
    AND a.valuenum IS NOT NULL
),
NadirCreatinine AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(creatinine_value) AS nadir_creatinine
  FROM
    CreatinineMeasurements
  GROUP BY
    subject_id,
    hadm_id
)
SELECT
  PERCENTILE_CONT(0.25, nadir_creatinine) AS iqr_25,
  PERCENTILE_CONT(0.75, nadir_creatinine) AS iqr_75
FROM
  NadirCreatinine
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      PatientInfo
  )
  AND hadm_id IN (
    SELECT
      hadm_id
    FROM
      Admissions
  );