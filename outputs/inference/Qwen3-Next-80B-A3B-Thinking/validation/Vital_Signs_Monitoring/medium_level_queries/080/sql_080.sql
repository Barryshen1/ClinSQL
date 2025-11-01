WITH filtered_stays AS (
  SELECT
    i.stay_id,
    i.intime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 56 AND 66
),
mean_map_per_stay AS (
  SELECT
    fs.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    filtered_stays fs
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    fs.stay_id = ce.stay_id
  WHERE
    ce.itemid = 456
    AND ce.charttime BETWEEN fs.intime AND fs.intime + INTERVAL '48' HOUR
  GROUP BY
    fs.stay_id
  HAVING
    COUNT(ce.valuenum) > 0
),
category_map AS (
  SELECT
    stay_id,
    mean_map,
    CASE
      WHEN mean_map < 65 THEN '<65'
      WHEN mean_map >= 65 AND mean_map < 75 THEN '65-74'
      WHEN mean_map >= 75 AND mean_map < 85 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM
    mean_map_per_stay
)
SELECT
  map_category,
  COUNT(*) AS count,
  AVG(mean_map) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_map) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mean_map) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY mean_map)) AS iqr
FROM
  category_map
GROUP BY
  map_category;