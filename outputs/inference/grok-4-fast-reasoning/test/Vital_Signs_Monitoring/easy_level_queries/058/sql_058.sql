WITH min_temps AS (
  SELECT 
    ce.stay_id, 
    MIN(ce.valuenum) AS min_temp_f
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON ce.stay_id = ic.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND di.label LIKE '%Temperature%'
    AND ce.valueuom = 'F'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ic.intime AND ic.outtime
  GROUP BY 
    ce.stay_id
  HAVING 
    min_temp_f IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(min_temp_f, 100)[OFFSET(50)] AS median_min_temp_f
FROM 
  min_temps;