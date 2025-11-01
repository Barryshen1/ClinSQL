WITH rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'respiratory rate'
    AND linksto = 'chartevents'
),
rr_48h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN rr_items ri
    ON ce.itemid = ri.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
categorized AS (
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '>=30'
    END AS rr_category
  FROM rr_48h
)
SELECT
  rr_category,
  COUNT(*) AS n_stays,
  AVG(avg_rr) AS mean_avg_rr,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(50)] AS median_avg_rr,
  (APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)]) AS iqr_avg_rr
FROM categorized
GROUP BY rr_category
ORDER BY
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;