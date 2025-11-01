WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 49 AND 59
),
AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%AMI%'
),
FirstTroponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS troponin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
  ON
    le.itemid = dli.itemid
  WHERE
    dli.label = 'Troponin T' AND le.valuenum > 0.04
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  p.subject_id,
  p.gender,
  p.anchor_age,
  a.admittime,
  a.diagnosis,
  ft.charttime AS first_troponin_time,
  ft.troponin_value AS first_troponin_value
FROM
  PatientInfo AS p
JOIN
  AdmissionInfo AS a
ON
  p.subject_id = a.subject_id
JOIN
  FirstTroponin AS ft
ON
  a.subject_id = ft.subject_id AND a.hadm_id = ft.hadm_id
ORDER BY
  p.subject_id,
  a.hadm_id;