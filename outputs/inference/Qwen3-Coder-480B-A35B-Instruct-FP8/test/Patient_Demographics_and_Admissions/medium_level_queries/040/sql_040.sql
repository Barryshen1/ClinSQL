WITH surgical_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
  ON
    a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND s.curr_service LIKE '%SURG%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE 'HOME%' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH') OR discharge_location LIKE '%FACILITY%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    surgical_admissions
)
SELECT
  discharge_category,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS los_ge_14,
  ROUND(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS prop_los_ge_7,
  ROUND(SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS prop_los_ge_14
FROM
  discharge_groups
WHERE
  discharge_category IN ('Home', 'Facility', 'In-hospital death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;