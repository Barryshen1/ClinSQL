WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.insurance,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'Medicare'
    AND a.dischtime IS NOT NULL  -- Ensure valid LOS
),
outcomes AS (
  SELECT 
    hadm_id,
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'SELF', 'HOME HEALTH CARE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB/DISTINCT PART HOSP', 'LONG TERM CARE HOSPITAL') THEN 'facility'
      ELSE 'other'
    END AS discharge_outcome
  FROM cohort
),
agg_stats AS (
  SELECT 
    discharge_outcome,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p75_los,
    APPROX_QUANTILES(los, 10)[OFFSET(9)] AS p90_los
  FROM outcomes
  WHERE discharge_outcome != 'other'  -- Exclude uncategorized
  GROUP BY discharge_outcome
),
percentile_10day AS (
  SELECT 
    PERCENT_RANK() OVER (ORDER BY los) * 100 AS percentile_10day
  FROM cohort
  WHERE los = 10
  LIMIT 1  -- Single value; assumes one row for the hypothetical patient
)
SELECT 
  s.*,
  (SELECT percentile_10day FROM percentile_10day) AS percentile_of_10day_stay
FROM agg_stats s
ORDER BY 
  CASE discharge_outcome 
    WHEN 'home' THEN 1 
    WHEN 'facility' THEN 2 
    WHEN 'in-hospital death' THEN 3 
  END
;