WITH cohort AS (
  SELECT
    CASE 
      WHEN a.hospital_expire_flag = 0 THEN 'Discharged Alive'
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    END AS mortality_stratum,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
    AND a.hospital_expire_flag IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
),
percentiles_cte AS (
  SELECT
    mortality_stratum,
    los_days,
    PERCENTILE_CONT(0.25) OVER (PARTITION BY mortality_stratum ORDER BY los_days) AS p25_los_days,
    PERCENTILE_CONT(0.50) OVER (PARTITION BY mortality_stratum ORDER BY los_days) AS p50_los_days,
    PERCENTILE_CONT(0.75) OVER (PARTITION BY mortality_stratum ORDER BY los_days) AS p75_los_days,
    PERCENTILE_CONT(0.90) OVER (PARTITION BY mortality_stratum ORDER BY los_days) AS p90_los_days
  FROM cohort
)
SELECT
  mortality_stratum,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  MAX(p25_los_days) AS p25_los_days,
  MAX(p50_los_days) AS p50_los_days,
  MAX(p75_los_days) AS p75_los_days,
  MAX(p90_los_days) AS p90_los_days
FROM percentiles_cte
GROUP BY mortality_stratum
ORDER BY 
  CASE mortality_stratum 
    WHEN 'Discharged Alive' THEN 1 
    WHEN 'In-Hospital Mortality' THEN 2 
  END;