WITH heart_rate_max_per_stay AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    MAX(ce.valuenum) AS max_heart_rate
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND di.label LIKE '%Heart Rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY p.subject_id, icu.stay_id
)
SELECT
  APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(3)]
  - APPROX_QUANTILES(max_heart_rate, 4)[OFFSET(1)] AS iqr_max_heart_rate
FROM heart_rate_max_per_stay;