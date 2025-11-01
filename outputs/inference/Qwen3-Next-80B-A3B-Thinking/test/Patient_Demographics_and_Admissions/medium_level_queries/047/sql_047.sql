SELECT
  category,
  AVG(los) AS mean_los,
  STDDEV_POP(los) AS sd_los,
  SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank_5_days
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'HOME'
      WHEN discharge_location IN ('REHAB', 'SKILLED NURSING FACILITY', 'OTHER FACILITY', 'HOSPICE') THEN 'FACILITY'
      ELSE NULL
    END AS category,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_location LIKE 'TRANSFER FROM OTHER%'
) subquery
WHERE category IS NOT NULL
GROUP BY category;