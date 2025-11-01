WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.insurance,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'Medicare'
    AND a.dischtime > a.admittime
),
cohort_with_outcome AS (
  SELECT 
    los,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE HOSPITAL', 'ACUTE CARE FACILITY') THEN 'facility'
      ELSE NULL
    END AS outcome
  FROM cohort
  WHERE los IS NOT NULL
)
SELECT DISTINCT
  outcome,
  COUNT(*) OVER (PARTITION BY outcome) AS n,
  ROUND(AVG(los) OVER (PARTITION BY outcome), 2) AS mean_los_days,
  PERCENTILE_CONT(los, 0.5) OVER (PARTITION BY outcome) AS median_los_days,
  PERCENTILE_CONT(los, 0.75) OVER (PARTITION BY outcome) AS p75_los_days,
  PERCENTILE_CONT(los, 0.9) OVER (PARTITION BY outcome) AS p90_los_days,
  ROUND(AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0.0 END) OVER (PARTITION BY outcome) * 100, 2) AS pct_le_10_days
FROM cohort_with_outcome
WHERE outcome IS NOT NULL
ORDER BY 
  CASE outcome 
    WHEN 'in-hospital death' THEN 1 
    WHEN 'home' THEN 2 
    WHEN 'facility' THEN 3 
  END;