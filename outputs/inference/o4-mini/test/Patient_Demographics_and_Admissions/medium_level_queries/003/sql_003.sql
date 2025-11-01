SELECT
  discharge_category,
  COUNT(*) AS n_patients,
  ROUND(AVG(los), 2) AS mean_los_days,
  -- Approximate percentiles via APPROX_QUANTILES
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los_days,
  ROUND(
    100.0 * SUM(CASE WHEN los <= 14 THEN 1 ELSE 0 END) / COUNT(*)
  , 1) AS pct_los_le_14d
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type != 'EMERGENCY'
) sub
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;