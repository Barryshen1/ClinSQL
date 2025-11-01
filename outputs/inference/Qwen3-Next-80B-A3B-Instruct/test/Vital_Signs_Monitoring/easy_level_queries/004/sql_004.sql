WITH temp_per_stay AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS mean_temperature
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND LOWER(di.label) LIKE '%temp%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45  -- reasonable physiological range
  GROUP BY 
    i.stay_id
)
SELECT 
  APPROX_QUANTILES(mean_temperature, 100)[OFFSET(75)] AS p75_mean_temperature
FROM 
  temp_per_stay;