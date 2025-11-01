WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.subject_id = s.subject_id
   AND a.hadm_id    = s.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND UPPER(a.admission_type) <> 'ELECTIVE'
    AND UPPER(s.curr_service) = 'MEDICINE'
)
SELECT DISTINCT
  discharge_category,
  ROUND(AVG(los_days) OVER (PARTITION BY discharge_category), 2) AS mean_los,
  PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY discharge_category) AS median_los,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_category) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY discharge_category) AS p90_los,
  ROUND(
    100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END)
          OVER (PARTITION BY discharge_category)
    / COUNT(*) OVER (PARTITION BY discharge_category),
    2
  ) AS pct_rank_7days
FROM
  cohort
ORDER BY
  discharge_category;