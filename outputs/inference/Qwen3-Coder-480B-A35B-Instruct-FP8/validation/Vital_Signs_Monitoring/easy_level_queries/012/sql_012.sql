WITH cohort AS (
  SELECT
    icu.stay_id,
    pat.subject_id,
    icu.intime,
    icu.outtime,
    icu.first_careunit
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND (icu.first_careunit LIKE '%Step%' OR icu.first_careunit LIKE '%IMC%')
),
diastolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%' AND category LIKE '%Blood Pressure%'
),
stay_diastolic_mean AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_diastolic
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    diastolic_items di
  ON
    ce.itemid = di.itemid
  JOIN
    cohort co
  ON
    ce.stay_id = co.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 200
  GROUP BY
    ce.stay_id
)
SELECT
  APPROX_QUANTILES(mean_diastolic, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(mean_diastolic, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(mean_diastolic, 4)[OFFSET(3)] - APPROX_QUANTILES(mean_diastolic, 4)[OFFSET(1)] AS IQR
FROM
  stay_diastolic_mean;