WITH patient_data AS (
  SELECT 
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
encounter_mortality AS (
  SELECT 
    hadm_id,
    hospital_expire_flag
  FROM 
    patient_data
),
mortality_rates AS (
  SELECT 
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) * 1.0 / COUNT(hadm_id) AS mortality_rate
  FROM 
    encounter_mortality
),
quantiles AS (
  SELECT 
    APPROX_QUANTILES(mortality_rate, 4) AS quantiles
  FROM 
    mortality_rates
)
SELECT 
  IF(ARRAY_LENGTH(quantiles.quantiles) >= 3, 
     quantiles.quantiles[OFFSET(3)] - quantiles.quantiles[OFFSET(1)], 
     NULL) AS interquartile_range
FROM 
  quantiles;