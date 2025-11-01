WITH patient_stays AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
),
rr_events AS (
  SELECT
    ps.stay_id,
    ce.valuenum AS rr_value
  FROM patient_stays ps
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ps.stay_id = ce.stay_id
    AND ce.itemid IN (220210, 224422)  -- Respiratory Rate itemIDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 100  -- Filter physiologically plausible values
    AND ce.charttime >= ps.intime
    AND ce.charttime <= DATETIME_ADD(ps.intime, INTERVAL 48 HOUR)
),
per_stay_avg AS (
  SELECT
    stay_id,
    AVG(rr_value) AS avg_rr
  FROM rr_events
  GROUP BY stay_id
  HAVING AVG(rr_value) IS NOT NULL  -- Ensure at least one valid measurement
),
categorized AS (
  SELECT
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      ELSE '>=30'
    END AS category
  FROM per_stay_avg
)
SELECT
  category,
  COUNT(stay_id) AS n,
  AVG(avg_rr) AS mean,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(75)] AS q3
FROM categorized
GROUP BY category
ORDER BY
  CASE category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    ELSE 4
  END;