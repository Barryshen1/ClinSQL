WITH outcome_groups AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    admission_location = 'EMERGENCY ROOM ADMISSION' AND
    gender = 'M' AND
    anchor_age BETWEEN 57 AND 67
)

SELECT
  discharge_outcome,
  COUNT(*) AS count,
  ROUND(AVG(los_days), 2) AS mean_los,
  ROUND(PERCENTILE_CONT(los_days, 0.5) OVER (PARTITION BY discharge_outcome), 2) AS median_los,
  ROUND(PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_outcome), 2) AS p75_los,
  ROUND(PERCENTILE_CONT(los_days, 0.9) OVER (PARTITION BY discharge_outcome), 2) AS p90_los
FROM
  outcome_groups
WHERE
  discharge_outcome IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY
  discharge_outcome, los_days
ORDER BY
  discharge_outcome;

-- Calculate percentile rank for 10 days
WITH percentile_rank_data AS (
  SELECT
    los_days,
    discharge_outcome,
    PERCENT_RANK() OVER (ORDER BY los_days) AS percentile_rank
  FROM
    outcome_groups
  WHERE
    discharge_outcome IN ('Home', 'Hospice', 'In-hospital death')
)
SELECT
  ROUND(percentile_rank * 100, 2) AS percentile_rank_for_10_days
FROM
  percentile_rank_data
WHERE
  los_days = 10
LIMIT 1;