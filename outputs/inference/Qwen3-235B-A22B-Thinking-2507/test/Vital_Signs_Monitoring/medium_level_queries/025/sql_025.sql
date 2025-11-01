WITH filtered_stays AS (
  SELECT 
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (
      p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)
    ) BETWEEN 82 AND 92
),
stay_temperatures AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 223762  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime <= fs.intime + INTERVAL 24 HOUR
  GROUP BY fs.stay_id
)
SELECT 
  (COUNTIF(avg_temp <= 37.5) * 100.0) / COUNT(*) AS percentile
FROM stay_temperatures;