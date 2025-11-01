WITH temp_events AS (
  SELECT 
    c.stay_id,
    MIN(ce.valuenum) AS min_temp_per_stay
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    c.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    c.subject_id = ce.subject_id 
    AND c.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.itemid IN (676, 677)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 70 AND 110
    AND ce.charttime BETWEEN c.intime AND c.outtime
  GROUP BY 
    c.stay_id
)
SELECT 
  PERCENTILE_CONT(min_temp_per_stay, 0.5) OVER () AS median_min_temp_f
FROM 
  temp_events;