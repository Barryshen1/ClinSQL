WITH heart_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
    AND linksto = 'chartevents'
),
cohort AS (
  SELECT icu.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
),
per_stay_mean_hr AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  JOIN heart_rate_items AS hr
    ON ce.itemid = hr.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT
  PERCENTILE_CONT(mean_hr, 0.5) OVER () AS median_of_per_stay_mean_hr
FROM per_stay_mean_hr
LIMIT 1;