WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.services`
      WHERE curr_service = 'MED'
    ) s
      ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'
    AND a.dischtime IS NOT NULL
),
los_calc AS (
  SELECT
    *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM cohort
),
discharge_grouped AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) IN (
        'snf', 'skilled nursing facility', 'rehab', 'rehabilitation', 'long term care hospital',
        'nursing home', 'icf', 'extended care', 'other facility', 'other hospital', 'short term hospital'
      ) THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM los_calc
)
SELECT
  discharge_group,
  COUNT(*) AS n_patients,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los,
  ROUND(100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_rank_7d
FROM
  discharge_grouped
WHERE
  discharge_group IN ('Home', 'Facility', 'In-hospital death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;