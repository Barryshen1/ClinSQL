SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(25)], 2) AS p25_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_rank_7day_in_percent
FROM (
  SELECT
    a.*,
    -- fractional LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(a.discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND UPPER(a.admission_type) IN ('EMERGENCY', 'URGENT')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
GROUP BY discharge_group
ORDER BY discharge_group;