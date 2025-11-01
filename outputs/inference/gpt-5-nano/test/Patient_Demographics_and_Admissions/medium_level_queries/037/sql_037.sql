WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE WHEN a.hospital_expire_flag = 1 THEN 'Died in-hospital' ELSE 'Discharged alive' END AS outcome_label,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
      ELSE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
    END AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type <> 'EMERGENCY'
    AND a.admittime IS NOT NULL
)

SELECT DISTINCT
  outcome_label,
  PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY outcome_label) AS p50,
  PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY outcome_label) AS p75,
  PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY outcome_label) AS p90,
  PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY outcome_label) AS p95,
  100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) OVER (PARTITION BY outcome_label) / COUNT(*) OVER (PARTITION BY outcome_label) AS percentile_rank_of_7_days
FROM base
ORDER BY outcome_label;