WITH map_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum,
    ce.charttime,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays ie
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND di.label IN ('Arterial Pressure mean', 'Non Invasive Blood Pressure mean', 'Manual Pulse Oximetry Mean')
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
),
stay_avg_map AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_map,
    COUNT(*) AS measurement_count
  FROM map_measurements
  GROUP BY stay_id
  HAVING COUNT(*) >= 3
)
SELECT 
  100.0 * SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_of_60
FROM stay_avg_map;