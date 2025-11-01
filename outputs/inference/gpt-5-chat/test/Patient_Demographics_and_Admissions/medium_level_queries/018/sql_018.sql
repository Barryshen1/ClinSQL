WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND UPPER(a.admission_location) = 'TRANSFER FROM OTHER HOSPITAL'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
classified AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM cohort
)
SELECT
  discharge_category,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los_days,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr_los_days_25,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS iqr_los_days_75,
  100 * COUNTIF(los_days <= 10) / COUNT(*) AS pct_los_le_10_days
FROM classified
GROUP BY discharge_category
ORDER BY discharge_category;