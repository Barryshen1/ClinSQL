WITH medicine_admissions AS (
  SELECT
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
    `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND s.curr_service = 'MED'
    AND a.admission_type = 'INPATIENT'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

discharge_categories AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%Home%' THEN 'Home'
      WHEN discharge_location LIKE '%Facility%' OR discharge_location LIKE '%Nursing%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    medicine_admissions
)

SELECT
  discharge_category,
  COUNT(*) AS admission_count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.25) OVER(), 2) AS percentile_25,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER(), 2) AS percentile_50,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER(), 2) AS percentile_75,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER(), 2) AS percentile_90,
  ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_le_10_days
FROM
  discharge_categories
GROUP BY
  discharge_category, hadm_id, los_days
ORDER BY
  discharge_category;