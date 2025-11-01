WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- fractional LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    -- non-elective: exclude explicit ELECTIVE admissions
    AND (a.admission_type IS NULL OR LOWER(a.admission_type) != 'elective')
    -- require valid times and non-negative LOS
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
    -- require the admission to have at least one "medicine" service entry
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND s.subject_id = a.subject_id
        AND LOWER(s.curr_service) LIKE '%med%'
    )
)
SELECT
  CASE WHEN hospital_expire_flag = 1 THEN 'died_in_hospital' ELSE 'discharged_alive' END AS outcome,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 3) AS mean_los_days,
  -- approximate percentiles (p50, p75, p90) using 100 quantile buckets
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los_days,
  -- percentile rank of a 5-day stay: percent of admissions with LOS <= 5 days
  ROUND(100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pctile_rank_of_5day_percent
FROM cohort
GROUP BY outcome
ORDER BY outcome;