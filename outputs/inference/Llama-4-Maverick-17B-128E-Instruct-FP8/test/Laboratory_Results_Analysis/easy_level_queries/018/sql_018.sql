WITH first_ph AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS ph_value,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie ON ce.stay_id = ie.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON ce.subject_id = p.subject_id
  WHERE 
    ce.itemid = 50821  
    AND p.gender = 'F'
)
SELECT 
  APPROX_QUANTILES(ph_value, 100)[OFFSET(50)] AS median_ph
FROM 
  first_ph
WHERE 
  rn = 1;