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
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR)/24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'
    AND (
      LOWER(a.admission_location) LIKE '%medicine%'
      OR LOWER(a.discharge_location) LIKE '%medicine%'
    )
    AND a.dischtime IS NOT NULL
),

discharge_categories AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%facility%' OR
           LOWER(discharge_location) LIKE '%nursing%' OR
           LOWER(discharge_location) LIKE '%rehab%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    medicine_inpatients
),

stats_by_category AS (
  SELECT
    discharge_category,
    COUNT(*) AS patient_count,
    AVG(los_days) AS mean_los,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_category) AS median_los,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_category) AS p75_los,
    PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY discharge_category) AS p90_los
  FROM
    discharge_categories
  GROUP BY
    discharge_category
),

percentile_ranks AS (
  SELECT
    discharge_category,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los_days) AS percentile_rank
  FROM
    discharge_categories
)

SELECT
  s.discharge_category,
  s.patient_count,
  ROUND(s.mean_los, 2) AS mean_los_days,
  ROUND(s.median_los, 2) AS median_los_days,
  ROUND(s.p75_los, 2) AS p75_los_days,
  ROUND(s.p90_los, 2) AS p90_los_days,
  ROUND(AVG(CASE WHEN p.los_days = 7 THEN p.percentile_rank ELSE NULL END)*100, 2) AS percentile_rank_for_7_days
FROM
  stats_by_category s
LEFT JOIN
  percentile_ranks p
ON
  s.discharge_category = p.discharge_category
GROUP BY
  s.discharge_category, s.patient_count, s.mean_los, s.median_los, s.p75_los, s.p90_los
ORDER BY
  s.discharge_category;