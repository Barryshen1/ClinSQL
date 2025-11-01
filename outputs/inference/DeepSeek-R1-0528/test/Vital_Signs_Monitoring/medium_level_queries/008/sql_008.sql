WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 39 AND 49
),

map_data AS (
  SELECT 
    c.stay_id,
    AVG(chart.valuenum) AS avg_map
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chart
    ON c.stay_id = chart.stay_id
  WHERE 
    chart.itemid IN (220181, 225312)  -- MAP item IDs
    AND chart.valuenum IS NOT NULL    -- Exclude non-numeric values
    AND chart.charttime >= c.intime
    AND chart.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
)

SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN NULL  -- Avoid division by zero
    ELSE (COUNTIF(avg_map <= 75) * 100.0) / COUNT(*) 
  END AS percentile
FROM map_data;