WITH map_first_48 AS (
  SELECT
    ie.stay_id,
    AVG(ie.valuenum) AS mean_map_first_48
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ie
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON ie.stay_id = icu.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND di.label LIKE '%MAP%'
    AND ie.valuenum IS NOT NULL
    AND ie.valuenum > 30
    AND ie.valuenum < 180
    AND ie.charttime >= icu.intime
    AND ie.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY
    ie.stay_id
),
binned AS (
  SELECT
    mean_map_first_48,
    CASE
      WHEN mean_map_first_48 < 65 THEN '<65'
      WHEN mean_map_first_48 >= 65 AND mean_map_first_48 < 75 THEN '65-74'
      WHEN mean_map_first_48 >= 75 AND mean_map_first_48 < 85 THEN '75-84'
      WHEN mean_map_first_48 >= 85 THEN '≥85'
    END AS map_category
  FROM
    map_first_48
)
SELECT
  map_category,
  COUNT(*) AS count,
  AVG(mean_map_first_48) AS mean_mean_map,
  PERCENTILE_CONT(mean_map_first_48, 0.5) WITHIN GROUP (ORDER BY mean_map_first_48) AS median_mean_map,
  PERCENTILE_CONT(mean_map_first_48, 0.75) WITHIN GROUP (ORDER BY mean_map_first_48) - PERCENTILE_CONT(mean_map_first_48, 0.25) WITHIN GROUP (ORDER BY mean_map_first_48) AS iqr_mean_map
FROM
  binned
GROUP BY
  map_category
ORDER BY
  map_category;