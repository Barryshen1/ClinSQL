SELECT
  discharge_outcome,
  MAX(median_los) AS median_los_days,
  MAX(q1_los) AS q1_los_days,
  MAX(q3_los) AS q3_los_days,
  MAX(pr14_percent) AS percentile_rank_of_14_days
FROM (
  SELECT
    discharge_outcome,
    PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_outcome) AS median_los,
    PERCENTILE_CONT(los_days, 0.25) OVER (PARTITION BY discharge_outcome) AS q1_los,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_outcome) AS q3_los,
    100.0 * SUM(CASE WHEN los_days <= 14.0 THEN 1 ELSE 0 END) OVER (PARTITION BY discharge_outcome)
      / COUNT(*) OVER (PARTITION BY discharge_outcome) AS pr14_percent
  FROM (
    SELECT
      CASE
        WHEN a.hospital_expire_flag = 1 OR a.deathtime IS NOT NULL THEN 'DEATH'
        WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'HOME'
        ELSE 'FACILITY'
      END AS discharge_outcome,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 43 AND 53
      AND a.admission_type = 'EMERGENCY'
      AND a.dischtime IS NOT NULL
      AND a.admittime <= a.dischtime
  )
)
GROUP BY discharge_outcome
ORDER BY discharge_outcome;