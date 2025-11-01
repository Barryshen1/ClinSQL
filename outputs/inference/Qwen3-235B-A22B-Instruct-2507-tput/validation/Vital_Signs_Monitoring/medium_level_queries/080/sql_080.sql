WITH patient_icu_stays AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    p.gender,
    (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) AS age_at_icu_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 56 AND 66
),
map_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum,
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%mean%arterial%pressure%'
    AND di.linksto = 'chartevents'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- physiologically valid MAP
),
map_first_48hr AS (
  SELECT 
    mis.stay_id,
    AVG(mm.valuenum) AS mean_map_48hr
  FROM patient_icu_stays mis
  JOIN map_measurements mm ON mis.stay_id = mm.stay_id
  WHERE mm.charttime >= mis.intime 
    AND mm.charttime < DATETIME_ADD(mis.intime, INTERVAL 48 HOUR)
  GROUP BY mis.stay_id
),
map_categories AS (
  SELECT 
    mean_map_48hr,
    CASE 
      WHEN mean_map_48hr < 65 THEN '<65'
      WHEN mean_map_48hr >= 65 AND mean_map_48hr <= 74 THEN '65-74'
      WHEN mean_map_48hr >= 75 AND mean_map_48hr <= 84 THEN '75-84'
      WHEN mean_map_48hr >= 85 THEN '>=85'
      ELSE NULL 
    END AS map_category
  FROM map_first_48hr
  WHERE mean_map_48hr IS NOT NULL
)
SELECT 
  map_category,
  COUNT(*) AS count_stays,
  ROUND(AVG(mean_map_48hr), 2) AS mean_mean_map,
  ROUND(PERCENTILE_CONT(mean_map_48hr, 0.5) OVER (PARTITION BY map_category), 2) AS median_mean_map,
  ROUND(
    PERCENTILE_CONT(mean_map_48hr, 0.75) OVER (PARTITION BY map_category) - 
    PERCENTILE_CONT(mean_map_48hr, 0.25) OVER (PARTITION BY map_category), 2
  ) AS iqr_mean_map
FROM map_categories
WHERE map_category IS NOT NULL
GROUP BY map_category, mean_map_48hr
ORDER BY map_category;