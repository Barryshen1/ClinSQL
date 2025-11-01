WITH female_transferred_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location LIKE '%TRANSFER%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

discharge_categories AS (
  SELECT
    subject_id,
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM
    female_transferred_patients
),

los_stats AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge7_count,
    ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*), 4) AS proportion_ge7,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los
  FROM
    discharge_categories
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  total_patients,
  los_ge7_count,
  proportion_ge7,
  p75_los
FROM
  los_stats
ORDER BY
  total_patients DESC;