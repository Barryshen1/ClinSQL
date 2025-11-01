WITH map_means AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    -- First 48 hours of ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    -- MAP measurements: label contains Mean arterial pressure or MAP
    AND REGEXP_CONTAINS(LOWER(di.label), '(mean arterial pressure|map)')
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)

SELECT
  CASE
    WHEN mean_map < 65 THEN '<65'
    WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
    WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
    WHEN mean_map >= 85 THEN '85+'
  END AS map_category,
  COUNT(*) AS n_stays,
  AVG(mean_map) AS category_mean_of_mean,
  APPROX_QUANTILES(mean_map, 100)[OFFSET(50)] AS category_median_of_mean,
  (APPROX_QUANTILES(mean_map, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_map, 100)[OFFSET(25)]) AS category_iqr
FROM map_means
GROUP BY
  CASE
    WHEN mean_map < 65 THEN '<65'
    WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
    WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
    WHEN mean_map >= 85 THEN '85+'
  END
ORDER BY
  CASE
    WHEN mean_map < 65 THEN '<65'
    WHEN mean_map BETWEEN 65 AND 74 THEN '65-74'
    WHEN mean_map BETWEEN 75 AND 84 THEN '75-84'
    WHEN mean_map >= 85 THEN '85+'
  END;