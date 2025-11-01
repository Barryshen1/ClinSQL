WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND a.hadm_id IS NOT NULL
),

outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('DISCH HOME, SELF CARE', 'DISCH HOME, NO FORMAL') 
        THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB/DISTINCT PART HOSP', 'LTAC') 
        OR REGEXP_CONTAINS(LOWER(discharge_location), r'(snf|rehab|ltac)') 
        THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_outcome
  FROM 
    cohort
)

SELECT 
  discharge_outcome,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 5)[OFFSET(2)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 5)[OFFSET(3)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 5)[OFFSET(4)], 2) AS p90_los_days,
  ROUND(
    SUM(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0 END) * 100.0 / COUNT(*), 
    2
  ) AS pct_los_le_7days
FROM 
  outcomes
WHERE 
  discharge_outcome IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
GROUP BY 
  discharge_outcome
ORDER BY 
  CASE discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'SNF/rehab/LTACH' THEN 2
    WHEN 'In-hospital death' THEN 3
  END;