WITH temp_events AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
    AND ce.itemid IN (676, 677, 678, 679, 3580, 223762, 223765)
    AND ce.valueuom = 'C'
    AND ce.valuenum IS NOT NULL
),
stay_averages AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM 
    temp_events
  GROUP BY 
    stay_id
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY cohort.avg_temp ASC) AS percentile_rank
FROM 
  (SELECT 36.0 AS avg_temp) target
CROSS JOIN 
  (SELECT avg_temp FROM stay_averages) cohort;