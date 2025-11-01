WITH medicine_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- Calculate LOS (adding 1 to count both admission and discharge days)
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    -- Male patients
    p.gender = 'M'
    -- Age 74-84
    AND p.anchor_age BETWEEN 74 AND 84
    -- Medicine inpatients (using admission or discharge location containing 'MED')
    AND (LOWER(a.admission_location) LIKE '%med%'
         OR LOWER(a.discharge_location) LIKE '%med%')
    -- Valid discharge time
    AND a.dischtime IS NOT NULL
),

discharge_categories AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    medicine_inpatients
)

SELECT
  discharge_category,
  COUNT(*) AS total_admissions,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median_los,
  SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) AS admissions_los_le_5,
  SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS prop_los_le_5
FROM
  discharge_categories
GROUP BY
  discharge_category, los_days
ORDER BY
  discharge_category;