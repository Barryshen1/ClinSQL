WITH cohort AS (
  SELECT 
    i.stay_id,
    i.intime,
    -- Calculate exact age at hospital admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 46 AND 56
),
temp_measurements AS (
  SELECT 
    CASE 
      WHEN ce.itemid = 223761 THEN (ce.valuenum * 9/5) + 32  -- Convert Celsius to Fahrenheit
      WHEN ce.itemid = 223762 THEN ce.valuenum  -- Already Fahrenheit
    END AS temp_f
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (223761, 223762)  -- Temperature item IDs
    AND ce.valuenum IS NOT NULL  -- Ensure numeric value exists
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)  -- First 24h
)
SELECT 
  APPROX_QUANTILES(temp_f, 100)[OFFSET(50)] AS median_temp
FROM temp_measurements;