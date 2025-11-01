WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.services` s 
      WHERE s.hadm_id = a.hadm_id 
        AND s.curr_service = 'MEDICINE'
    )
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
    WHEN discharge_location = 'DISCH HOME' THEN 'home'
    ELSE 'facility'
  END AS discharge_category,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  (COUNTIF(los_days <= 7) * 100.0 / COUNT(*)) AS percentile_rank_7days_pct
FROM 
  qualifying_admissions
GROUP BY 
  discharge_category
ORDER BY 
  discharge_category;