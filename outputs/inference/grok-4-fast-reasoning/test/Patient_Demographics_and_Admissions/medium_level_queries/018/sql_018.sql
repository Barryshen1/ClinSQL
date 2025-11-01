WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'TRANSFER FROM HOSP'
    AND a.admission_type != 'NEWBORN'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 0
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN REGEXP_CONTAINS(discharge_location, r'(?i)home') THEN 'Home'
      ELSE 'Facility'
    END AS discharge_cat,
    100.0 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) OVER() / COUNT(*) OVER() AS overall_pct_le10
  FROM cohort
)
SELECT 
  discharge_cat,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los_days,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS iqr_25_days,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS iqr_75_days,
  COUNT(*) AS n_admissions,
  ROUND(MIN(overall_pct_le10), 2) AS overall_pct_los_le10_days
FROM categorized
GROUP BY discharge_cat
ORDER BY 
  CASE discharge_cat 
    WHEN 'Home' THEN 1 
    WHEN 'Facility' THEN 2 
    WHEN 'In-hospital death' THEN 3 
  END;