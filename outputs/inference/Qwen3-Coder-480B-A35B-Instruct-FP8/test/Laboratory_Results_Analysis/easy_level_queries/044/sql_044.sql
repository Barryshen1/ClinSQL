WITH ischemic_stroke_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('434', '436'))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),

glucose_on_discharge_day AS (
  SELECT
    l.valuenum
  FROM
    ischemic_stroke_admissions i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON i.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'glucose'
    AND LOWER(d.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND DATE(l.charttime) = DATE(i.dischtime)
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM
  glucose_on_discharge_day;