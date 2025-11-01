WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    a.deathtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.dischtime IS NOT NULL
    -- Identify transfer-ins (heuristic: inbound transfer events)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.transfers` AS t
      WHERE t.subject_id = a.subject_id
        AND t.hadm_id = a.hadm_id
        AND LOWER(t.eventtype) LIKE '%in%'
    )
),
los_calc AS (
  SELECT
    bc.subject_id,
    bc.hadm_id,
    bc.admittime,
    bc.dischtime,
    bc.discharge_location,
    bc.hospital_expire_flag,
    bc.deathtime,
    TIMESTAMP_DIFF(bc.dischtime, bc.admittime, DAY) AS LOS_days
  FROM base_cohort bc
)
SELECT
  discharge_group,
  COUNT(*) AS n_total,
  AVG(LOS_days) AS mean_los_days,
  (APPROX_QUANTILES(LOS_days, 100))[OFFSET(25)] AS p25_days,
  (APPROX_QUANTILES(LOS_days, 100))[OFFSET(50)] AS median_days,
  (APPROX_QUANTILES(LOS_days, 100))[OFFSET(75)] AS p75_days,
  (APPROX_QUANTILES(LOS_days, 100))[OFFSET(90)] AS p90_days,
  (APPROX_QUANTILES(LOS_days, 100))[OFFSET(95)] AS p95_days,
  SUM(CASE WHEN LOS_days <= 5 THEN 1.0 ELSE 0.0 END) / COUNT(*) AS percentile_rank_5day
FROM (
  SELECT
    CASE
      WHEN discharge_location = 'Home' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'Rehab', 'LTACH') THEN 'SNF/Rehab/LTACH'
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'In-hospital Mortality'
      ELSE NULL
    END AS discharge_group,
    LOS_days
  FROM los_calc
) AS sub
WHERE discharge_group IS NOT NULL
GROUP BY discharge_group
ORDER BY discharge_group;