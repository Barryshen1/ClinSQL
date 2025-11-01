WITH first_map AS (
  SELECT 
    p.subject_id,
    c.valuenum AS first_map_value,
    ROW_NUMBER() OVER (
      PARTITION BY i.subject_id, i.stay_id 
      ORDER BY c.charttime ASC
    ) AS row_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id 
    AND i.stay_id = c.stay_id
    AND i.hadm_id = c.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND c.itemid = 220052  -- MAP
    AND c.valuenum IS NOT NULL 
    AND c.valuenum > 0
    AND c.charttime >= i.intime
    AND c.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 1 HOUR)
)
SELECT 
  STDDEV(first_map_value) AS sd_first_map
FROM 
  first_map
WHERE 
  row_num = 1;