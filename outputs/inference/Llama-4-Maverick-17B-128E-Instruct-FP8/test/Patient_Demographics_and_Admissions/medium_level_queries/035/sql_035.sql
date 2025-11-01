WITH 
-- Filter patients and calculate LOS
patient_los AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),
-- Classify discharge outcome
discharge_outcome AS (
  SELECT 
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN discharge_location IN ('DEAD/EXPIRED', 'DEATH', 'EXP') THEN 'death'
      WHEN LOWER(discharge_location) LIKE '%facility%' OR LOWER(discharge_location) LIKE '%nursing%' THEN 'facility'
      ELSE 'home'
    END AS discharge_outcome
  FROM 
    patient_los
)

-- Final query to extract required statistics
SELECT 
  discharge_outcome,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr_los,
  COUNTIF(los_days <= 14) / COUNT(*) * 100 AS percentile_rank_14days
FROM 
  discharge_outcome
GROUP BY 
  discharge_outcome
ORDER BY 
  discharge_outcome;