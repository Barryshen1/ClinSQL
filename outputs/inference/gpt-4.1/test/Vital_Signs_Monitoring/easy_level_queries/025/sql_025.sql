WITH resp_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

female_39_49 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 39 AND 49
),

mean_resp_rate_per_stay AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN female_39_49 f
    ON icu.subject_id = f.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.hadm_id = ce.hadm_id
    AND icu.stay_id = ce.stay_id
  JOIN resp_rate_items ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY icu.stay_id
)

SELECT
  PERCENTILE_CONT(mean_resp_rate, 0.75) OVER() AS percentile_75_mean_resp_rate
FROM mean_resp_rate_per_stay;