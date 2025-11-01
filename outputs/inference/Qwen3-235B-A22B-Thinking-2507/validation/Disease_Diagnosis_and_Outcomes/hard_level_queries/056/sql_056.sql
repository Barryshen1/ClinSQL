WITH base AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    -- Calculate age at admission using anchor variables
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age,
    -- 90-day mortality using patients.dod (covers post-discharge deaths)
    CASE 
      WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(CAST(p.dod AS TIMESTAMP), CAST(a.admittime AS TIMESTAMP), DAY) <= 90 
      THEN 1 ELSE 0 
    END AS mortality_90d,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- Only male patients
),
base_filtered AS (
  SELECT *
  FROM base
  WHERE age BETWEEN 63 AND 73  -- Age filter: 63-73 years
),
diagnoses_count AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
septic_shock AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code = 'R6521'  -- Septic shock ICD-10 code (without dot)
),
complications AS (
  SELECT 
    hadm_id,
    1 AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN (
    'N170','N171','N172','N178','N179',  -- AKI codes
    'J9600','J9601','J9602','J9610','J9611','J9612','J9620','J9621','J968','J969'  -- Resp failure
  )
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    b.*,
    COALESCE(dc.num_diagnoses, 0) AS num_diagnoses,
    ss.hadm_id IS NOT NULL AS has_septic_shock,
    COALESCE(c.has_complication, 0) AS has_complication
  FROM base_filtered b
  LEFT JOIN diagnoses_count dc 
    ON b.hadm_id = dc.hadm_id
  LEFT JOIN septic_shock ss 
    ON b.hadm_id = ss.hadm_id
  LEFT JOIN complications c 
    ON b.hadm_id = c.hadm_id
)

SELECT 
  -- Group of interest metrics (septic shock + >15 diagnoses)
  AVG(CASE WHEN has_septic_shock AND num_diagnoses > 15 THEN num_diagnoses END) AS mean_risk_score,
  AVG(CASE WHEN has_septic_shock AND num_diagnoses > 15 THEN mortality_90d END) AS mortality_90d_rate,
  AVG(CASE WHEN has_septic_shock AND num_diagnoses > 15 THEN has_complication END) AS major_complication_rate,
  AVG(CASE WHEN has_septic_shock AND num_diagnoses > 15 AND mortality_90d = 0 THEN los END) AS survivor_los,
  
  -- Reference group metrics (all male 63-73 excluding group of interest)
  AVG(CASE WHEN NOT has_septic_shock OR num_diagnoses <= 15 THEN has_complication END) AS major_complication_rate_ref,
  AVG(CASE WHEN NOT has_septic_shock OR num_diagnoses <= 15 THEN 
          CASE WHEN mortality_90d = 0 THEN los END 
        END) AS survivor_los_ref,
  
  -- Percentile for 16 diagnoses in reference group (male 63-73 excluding group of interest)
  COUNTIF(num_diagnoses <= 16 AND (NOT has_septic_shock OR num_diagnoses <= 15)) * 100.0 / 
  COUNTIF(NOT has_septic_shock OR num_diagnoses <= 15) AS percentile_16_ref
FROM combined
WHERE num_diagnoses > 0  -- Exclude admissions with no diagnoses (theoretical edge case);