WITH female_39_49 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 39 AND 49
),
resp_rate_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%resp%' AND LOWER(label) LIKE '%rate%'
),
mean_rr_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN female_39_49 p
    ON ce.subject_id = p.subject_id
  JOIN resp_rate_itemids ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY ce.stay_id
)
SELECT
  PERCENTILE_CONT(mean_rr, 0.75) OVER() AS p75_mean_rr
FROM mean_rr_per_stay;