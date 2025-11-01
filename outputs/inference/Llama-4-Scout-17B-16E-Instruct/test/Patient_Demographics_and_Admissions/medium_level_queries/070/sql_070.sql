WITH 
  admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admit_provider_id,
      a.admission_location,
      a.discharge_location,
      a.hospital_expire_flag,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),
  
  stays AS (
    SELECT 
      a.hadm_id,
      ic.stay_id,
      ic.intime,
      ic.outtime,
      TIMESTAMPDIFF(DAY, ic.intime, ic.outtime) AS los_days
    FROM 
      admissions a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON 
      a.hadm_id = ic.hadm_id
  ),
  
  stays_with_los AS (
    SELECT 
      s.hadm_id,
      s.stay_id,
      s.los_days,
      a.discharge_location
    FROM 
      stays s
    INNER JOIN 
      admissions a
    ON 
      s.hadm_id = a.hadm_id
    WHERE 
      a.anchor_age BETWEEN 57 AND 67
      AND a.gender = 'M'
      AND a.discharge_location IN ('Home', 'Hospice', 'Expired')
  ),

  -- Calculate percentile rank for a LOS of 10 days
  los_stats AS (
    SELECT 
      discharge_location,
      AVG(los_days) AS mean_los,
      PERCENTILE_CONT(0.5)(los_days) AS median_los,
      PERCENTILE_CONT(0.75)(los_days) AS p75_los,
      PERCENTILE_CONT(0.9)(los_days) AS p90_los
    FROM 
      stays_with_los
    GROUP BY 
      discharge_location
  ),

  los_percentile_rank AS (
    SELECT 
      discharge_location,
      los_days,
      PERCENT_RANK() OVER (PARTITION BY discharge_location ORDER BY los_days) AS percentile_rank
    FROM 
      stays_with_los
  )

SELECT 
  'Mean LOS' AS metric,
  discharge_location,
  mean_los AS value
FROM 
  los_stats
UNION ALL
SELECT 
  'Median LOS' AS metric,
  discharge_location,
  median_los AS value
FROM 
  los_stats
UNION ALL
SELECT 
  'P75 LOS' AS metric,
  discharge_location,
  p75_los AS value
FROM 
  los_stats
UNION ALL
SELECT 
  'P90 LOS' AS metric,
  discharge_location,
  p90_los AS value
FROM 
  los_stats
UNION ALL
SELECT 
  'Percentile Rank for 10 days' AS metric,
  discharge_location,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS percentile_rank
FROM 
  stays_with_los
GROUP BY 
  discharge_location;