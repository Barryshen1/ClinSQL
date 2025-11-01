WITH filtered_admissions AS (
  SELECT 
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 'Died'
      ELSE 'Survived'
    END AS discharge_status
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
)
SELECT 
  discharge_status,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95,
  COUNTIF(los_days <= 7) / COUNT(*) AS percentile_rank_7days
FROM 
  filtered_admissions
GROUP BY 
  discharge_status
ORDER BY 
  discharge_status;