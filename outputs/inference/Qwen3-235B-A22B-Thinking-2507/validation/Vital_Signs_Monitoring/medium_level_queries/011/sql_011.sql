WITH filtered_stays AS (
  SELECT 
    icustays.stay_id,
    icustays.intime,
    (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year + patients.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year + patients.anchor_age) BETWEEN 54 AND 64
),

rr_measurements AS (
  SELECT 
    fs.stay_id,
    ce.valuenum AS rr
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE ce.itemid = 220210
    AND ce.charttime >= fs.intime
    AND ce.charttime <= DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

stay_avg_rr AS (
  SELECT 
    stay_id,
    AVG(rr) AS avg_rr
  FROM rr_measurements
  GROUP BY stay_id
),

categorized_rr AS (
  SELECT 
    stay_id,
    avg_rr,
    CASE 
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr < 21 THEN '12-20'
      WHEN avg_rr < 30 THEN '21-29'
      ELSE '>=30'
    END AS rr_category
  FROM stay_avg_rr
)

SELECT 
  rr_category,
  COUNT(*) AS n,
  AVG(avg_rr) AS mean_rr,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(50)] AS median_rr,
  APPROX_QUANTILES(avg_rr, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_rr, 100)[OFFSET(25)] AS iqr
FROM categorized_rr
GROUP BY rr_category
ORDER BY 
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;