WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 39
    AND anchor_age <= 49
),
rr_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
     OR LOWER(label) LIKE '%resp rate%'
),
qualifying_stays AS (
  SELECT stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN qualifying_patients pat ON icu.subject_id = pat.subject_id
),
mean_rr_per_stay AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN qualifying_stays qs ON ce.stay_id = qs.stay_id
  INNER JOIN rr_itemids rr ON ce.itemid = rr.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
  HAVING mean_rr IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(mean_rr, 4)[OFFSET(3)] AS p75_mean_respiratory_rate_per_stay
FROM mean_rr_per_stay;