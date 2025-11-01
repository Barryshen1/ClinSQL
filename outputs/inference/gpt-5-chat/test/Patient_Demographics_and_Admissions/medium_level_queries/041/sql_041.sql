WITH elective_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  ROUND(AVG(los_days),2) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  ROUND(COUNTIF(los_days <= 7) / COUNT(*) * 100,2) AS pct_los_le_7
FROM (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%skilled nursing%'
        OR LOWER(discharge_location) LIKE '%snf%'
        OR LOWER(discharge_location) LIKE '%rehab%'
        OR LOWER(discharge_location) LIKE '%long term acute%'
        OR LOWER(discharge_location) LIKE '%ltach%' THEN 'SNF/rehab/LTACH'
      ELSE 'Other'
    END AS discharge_category
  FROM elective_admissions
  WHERE los_days >= 0
)
WHERE discharge_category IN ('Home', 'SNF/rehab/LTACH', 'In-hospital death')
GROUP BY discharge_category
ORDER BY discharge_category;