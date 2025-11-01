WITH first_24h_map AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND ce.itemid = 220181  -- Mean arterial pressure (MAP)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.stay_id
)
SELECT STDDEV(mean_map) AS std_dev_first_24h_map
FROM first_24h_map;