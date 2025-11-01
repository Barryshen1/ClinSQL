SELECT
  day1_icu_status,
  CASE
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 5 THEN 'LOS <= 5 days'
    ELSE 'LOS > 5 days'
  END AS los_category,
  COUNT(CASE WHEN hospital_expire_flag = TRUE THEN 1 END) * 100.0 / COUNT(*) AS mortality_percentage,
  PERCENTILE_CONT(TIMESTAMP_DIFF(dischtime, admittime, DAY), 0.5) AS median_los
FROM ICUStayInfo
GROUP BY
  day1_icu_status,
  los_category
ORDER BY
  day1_icu_status,
  los_category;