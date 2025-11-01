WITH avg_rr_per_stay AS (
  SELECT
    icustays.stay_id,
    AVG(chartevents.valuenum) AS avg_rr
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icustays.stay_id = chartevents.stay_id
    AND chartevents.itemid = 220210
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.intime + INTERVAL 48 HOUR
  WHERE
    patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 54 AND 64
  GROUP BY
    icustays.stay_id
  HAVING
    avg_rr IS NOT NULL
),
categorized AS (
  SELECT
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
      ELSE '>=30'
    END AS rr_category,
    avg_rr
  FROM
    avg_rr_per_stay
)
SELECT
  rr_category,
  COUNT(*) AS n,
  AVG(avg_rr) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_rr) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_rr) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY avg_rr) AS iqr
FROM
  categorized
GROUP BY
  rr_category;