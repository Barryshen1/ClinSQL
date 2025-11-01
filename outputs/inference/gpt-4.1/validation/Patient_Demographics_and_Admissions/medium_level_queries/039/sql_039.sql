WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    a.admission_type,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, classified AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM cohort
  WHERE los IS NOT NULL AND los >= 0
)
, stats AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n_admissions,
    ROUND(AVG(los), 2) AS mean_los,
    -- Get percentiles
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS los_25th,
    APPROX_QUANTILES(los, 4)[OFFSET(2)] AS los_50th,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_75th
  FROM classified
  GROUP BY discharge_outcome
)
, percentile_rank_7d AS (
  SELECT
    discharge_outcome,
    -- Percentile rank of 7-day LOS among admissions in each outcome group
    ROUND(
      SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*)
    , 4) AS percentile_rank_7d
  FROM classified
  GROUP BY discharge_outcome
)
SELECT
  s.discharge_outcome,
  s.n_admissions,
  s.mean_los,
  s.los_25th,
  s.los_50th,
  s.los_75th,
  pr.percentile_rank_7d
FROM stats s
LEFT JOIN percentile_rank_7d pr
  ON s.discharge_outcome = pr.discharge_outcome
ORDER BY
  -- Show Home, Facility, Death in order
  CASE s.discharge_outcome
    WHEN 'Home' THEN 1
    WHEN 'Facility' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END
;