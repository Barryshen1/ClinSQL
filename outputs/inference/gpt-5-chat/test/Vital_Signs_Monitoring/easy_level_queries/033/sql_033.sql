WITH heart_rate_data AS (
  SELECT
    ce.valuenum AS hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND ce.itemid IN (211, 220045) -- Heart Rate itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    -- ICU day 2+ filter: events at least 24 hours after ICU admission
    AND TIMESTAMP_DIFF(ce.charttime, icu.intime, HOUR) >= 24
)
SELECT
  q[2] - q[0] AS iqr_heart_rate,
  q[0] AS q1,
  q[2] AS q3
FROM (
  SELECT APPROX_QUANTILES(hr, 4) AS q
  FROM heart_rate_data
);