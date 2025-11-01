WITH 
-- Define sepsis and calculate LOS
sepsis_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    TIMESTAMPDIFF(DAY, icu.intime, icu.outtime) AS los,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '995.91'  -- Sepsis
        OR icd_code LIKE '998.0'  -- Postprocedural infection
        OR icd_code LIKE '999.3'  -- Infection due to central line
        OR icd_code LIKE '481'   -- Pneumonia
        OR icd_code LIKE '482'   -- Pneumonia due to bacteria
        OR icd_code LIKE '483'   -- Pneumonia due to virus
        OR icd_code LIKE '484'   -- Pneumonia due to fungus
        OR icd_code LIKE '485'   -- Pneumonia with no organism
        OR icd_code LIKE '486'   -- Pneumonia, organism unspecified
    )
    AND a.hadm_id NOT IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE '785.52'  -- Septic shock
    )
),

-- Categorize patients by LOS and calculate mortality
los_mortality AS (
  SELECT 
    CASE 
      WHEN los <= 7 THEN 'LOS_7'
      ELSE 'LOS_>7'
    END AS los_category,
    hospital_expire_flag,
    intime,
    outtime
  FROM 
    sepsis_patients
)

-- Calculate mortality rates
SELECT 
  los_category,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  (SUM(hospital_expire_flag) * 1.0 / COUNT(*)) * 100 AS mortality_rate
FROM 
  los_mortality
GROUP BY 
  los_category;

-- Absolute and relative difference
WITH mortality_rates AS (
  SELECT 
    los_category,
    (SUM(hospital_expire_flag) * 1.0 / COUNT(*)) * 100 AS mortality_rate
  FROM 
    los_mortality
  GROUP BY 
    los_category
)
SELECT 
  los_category,
  mortality_rate,
  LAG(mortality_rate) OVER (ORDER BY los_category) AS prev_mortality_rate,
  ((mortality_rate - LAG(mortality_rate) OVER (ORDER BY los_category)) / 
   LAG(mortality_rate) OVER (ORDER BY los_category)) * 100 AS relative_difference,
  mortality_rate - LAG(mortality_rate) OVER (ORDER BY los_category) AS absolute_difference
FROM 
  mortality_rates
ORDER BY 
  los_category;

-- Median time-to-death
WITH time_to_death AS (
  SELECT 
    los_category,
    DATE_DIFF(outtime, intime) AS time_to_death
  FROM 
    los_mortality
  WHERE 
    hospital_expire_flag = 1
)
SELECT 
  los_category,
  APPROX_QUANTILES(time_to_death, 0.5) AS median_time_to_death
FROM 
  time_to_death
GROUP BY 
  los_category;