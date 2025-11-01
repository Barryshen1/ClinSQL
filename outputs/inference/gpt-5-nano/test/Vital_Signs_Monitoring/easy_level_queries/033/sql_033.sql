WITH cohort AS (
  -- Identify ICU stays for female patients aged 45-55
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
)

SELECT
  CAST(q[OFFSET(1)] AS FLOAT64) AS q1_heart_rate,
  CAST(q[OFFSET(3)] AS FLOAT64) AS q3_heart_rate,
  CAST(q[OFFSET(3)] - q[OFFSET(1)] AS FLOAT64) AS iqr_heart_rate
FROM (
  SELECT
    APPROX_QUANTILES(hr.valuenum, 4) AS q
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS hr
    ON hr.subject_id = c.subject_id
   AND hr.hadm_id = c.hadm_id
   AND hr.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON hr.itemid = di.itemid
  WHERE
    hr.valuenum IS NOT NULL
    AND (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.abbreviation) LIKE '%hr%')
    -- ICU day 2 or later
    AND TIMESTAMP_DIFF(hr.charttime, c.intime, DAY) >= 2
) ;