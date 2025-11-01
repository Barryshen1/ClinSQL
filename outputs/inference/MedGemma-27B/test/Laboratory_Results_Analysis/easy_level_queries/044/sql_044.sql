WITH StrokeAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    d.icd_code AS diagnosis_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 94
    AND d.icd_code LIKE 'I63%' -- Ischemic stroke codes
), GlucoseMeasurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum AS glucose_value,
    le.valueuom AS glucose_uom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Glucose'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
), DischargeDayGlucose AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.dischtime,
    gm.glucose_value
  FROM
    StrokeAdmissions AS sa
  INNER JOIN
    GlucoseMeasurements AS gm ON sa.subject_id = gm.subject_id AND sa.hadm_id = gm.hadm_id
  WHERE
    DATE(gm.charttime) = DATE(sa.dischtime)
)
SELECT
  PERCENTILE_CONT(0.25, glucose_value) AS iqr_25,
  PERCENTILE_CONT(0.75, glucose_value) AS iqr_75
FROM
  DischargeDayGlucose;