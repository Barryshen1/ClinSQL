WITH min_temp_per_stay AS (
  SELECT 
    i.stay_id,
    MIN(ce.valuenum * 9/5 + 32) AS min_temperature_f
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND di.label = 'Temperature'
    AND ce.valuenum BETWEEN 21 AND 46
  GROUP BY 
    i.stay_id
)
SELECT 
  PERCENTILE_CONT(min_temperature_f, 0.5) AS median_min_temperature_f
FROM 
  min_temp_per_stay;