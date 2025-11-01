WITH filtered_icu AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 85 AND 95
),
map_data AS (
  SELECT 
    f.stay_id,
    c.valuenum
  FROM filtered_icu f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    c.charttime >= f.intime 
    AND c.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
    AND d.label = 'Arterial Pressure mean'
    AND c.valuenum IS NOT NULL
),
patient_avg AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_map
  FROM map_data
  GROUP BY stay_id
)
SELECT 
  STDDEV(avg_map) AS stddev_mean_map_24h
FROM patient_avg;