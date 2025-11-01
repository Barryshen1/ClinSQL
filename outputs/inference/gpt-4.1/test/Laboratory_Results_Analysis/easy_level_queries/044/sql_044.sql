WITH ischemic_stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 94
    AND (
      -- ICD-10: I63.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I63'))
      -- ICD-9: 434.x1 (ischemic stroke)
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^434'))
    )
)

, serum_glucose_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'glucose'
    AND LOWER(fluid) = 'serum'
)

, discharge_day_glucose AS (
  SELECT
    isa.subject_id,
    isa.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    ischemic_stroke_admissions isa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON isa.subject_id = l.subject_id
      AND isa.hadm_id = l.hadm_id
    INNER JOIN serum_glucose_itemids sgi
      ON l.itemid = sgi.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(isa.dischtime)
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS glucose_25th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS glucose_75th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS glucose_IQR
FROM
  discharge_day_glucose
;