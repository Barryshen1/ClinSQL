WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
),
DiagnosisInfo AS (
  SELECT
    subject_id,
    hadm_id,
    icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code LIKE '414%'
),
TroponinInfo AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    valuenum AS troponin_t_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 50178 -- Troponin T
),
FirstTroponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_troponin_time,
    MIN(troponin_t_value) AS first_troponin_value
  FROM
    TroponinInfo
  GROUP BY
    subject_id,
    hadm_id
),
RelevantPatients AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    PatientInfo AS p
  JOIN
    DiagnosisInfo AS d
    ON p.subject_id = d.subject_id
  JOIN
    FirstTroponin AS ft
    ON p.subject_id = ft.subject_id
    AND d.hadm_id = ft.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND ft.first_troponin_value > 0.014
)
SELECT
  PERCENTILE_CONT(0.5, first_troponin_value) AS median_troponin_t,
  PERCENTILE_CONT(0.25, first_troponin_value) AS iqr_25,
  PERCENTILE_CONT(0.75, first_troponin_value) AS iqr_75
FROM
  FirstTroponin AS ft
JOIN
  RelevantPatients AS rp
  ON ft.subject_id = rp.subject_id
  AND ft.hadm_id = rp.hadm_id;