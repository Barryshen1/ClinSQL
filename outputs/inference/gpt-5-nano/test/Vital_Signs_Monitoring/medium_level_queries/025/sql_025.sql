WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  WHERE
    LOWER(p.gender) = 'male'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- 2) For each ICU stay, compute the average temperature in the first 24 hours
--    of the ICU stay by pulling charted temperature measurements
per_stay_temp AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_temp_c
  FROM
    cohort AS c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE
    ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
  -- Keep only stays with at least one temperature measurement in the first 24 hours
  HAVING
    COUNT(*) > 0
)

-- 3) Compute the percentile of 37.5°C relative to the per-stay averages
SELECT
  100.0 * SAFE_DIVIDE(
    SUM(CASE WHEN avg_temp_c <= 37.5 THEN 1 ELSE 0 END),
    COUNT(*)  -- total stays with a first-24h avg temp
  ) AS percentile_37_5_in_first_24h
FROM per_stay_temp;