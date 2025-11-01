WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_categories AS (
  SELECT
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END IS NOT NULL
)
SELECT
  discharge_category,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  AVG(CASE WHEN los < 5 THEN 1.0 ELSE 0 END) * 100 AS percent_los_less_than_5_days
FROM
  discharge_categories
GROUP BY
  discharge_category
ORDER BY
  discharge_category;