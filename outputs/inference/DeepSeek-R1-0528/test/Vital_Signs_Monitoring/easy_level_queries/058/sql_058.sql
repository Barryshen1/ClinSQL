WITH temp_per_stay AS (
  SELECT 
    ie.stay_id,
    MIN(ce.valuenum) AS min_temp_f
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
    ON p.subject_id = ie.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.itemid IN (223761, 223762)  -- Temperature in °F
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude implausible low values
  GROUP BY ie.stay_id
)
SELECT 
  APPROX_QUANTILES(min_temp_f, 100)[OFFSET(50)] AS median_min_temp_f
FROM temp_per_stay;