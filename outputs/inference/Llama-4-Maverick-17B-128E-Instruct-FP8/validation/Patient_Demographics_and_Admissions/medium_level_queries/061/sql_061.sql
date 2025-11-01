WITH 
-- Filter admissions based on age, gender, and admission type
filtered_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.discharge_location, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 86 AND 96 AND a.admission_type = 'URGENT'
),

-- Calculate LOS and discharge outcome
admission_outcomes AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death' 
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHABILITATION') THEN 'Facility'
      ELSE 'Other'
    END AS final_discharge_outcome
  FROM filtered_admissions
),

-- Calculate percentile rank for 10-day stay
los_percentile AS (
  SELECT 
    final_discharge_outcome,
    los,
    PERCENT_RANK() OVER (PARTITION BY final_discharge_outcome ORDER BY los) AS los_percentile
  FROM admission_outcomes
)

-- Calculate statistics for LOS by discharge outcome and around 10-day stay percentile
SELECT 
  final_discharge_outcome,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
FROM los_percentile
WHERE ABS(los_percentile - 0.5) <= 0.05  -- Filter around the 10-day stay percentile
GROUP BY final_discharge_outcome

UNION ALL

SELECT 
  final_discharge_outcome,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
FROM admission_outcomes
GROUP BY final_discharge_outcome;