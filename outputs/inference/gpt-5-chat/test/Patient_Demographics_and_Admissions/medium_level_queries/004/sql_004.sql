WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  AVG(los) AS mean_los,
  quantiles[OFFSET(50)] AS median_los,
  quantiles[OFFSET(75)] AS p75_los,
  quantiles[OFFSET(90)] AS p90_los,
  100.0 * SUM(CASE WHEN los < 5 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_lt_5d
FROM (
  SELECT
    CASE
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category,
    los
  FROM cohort
) t
JOIN (
  SELECT
    CASE
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      WHEN discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_category,
    APPROX_QUANTILES(los, 100) AS quantiles
  FROM cohort
  GROUP BY discharge_category
) q
USING (discharge_category)
GROUP BY discharge_category, quantiles
ORDER BY discharge_category;