WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admission_type,
    a.hospital_expire_flag,
    LOWER(COALESCE(a.discharge_location, '')) AS discharge_location,
    -- fractional LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

classified AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN hospital_expire_flag = 0
           AND (discharge_location LIKE '%home%') THEN 'home'
      WHEN hospital_expire_flag = 0
           AND (
             discharge_location LIKE '%nurs%'
             OR discharge_location LIKE '%skilled%'
             OR discharge_location LIKE '%snf%'
             OR discharge_location LIKE '%rehab%'
             OR discharge_location LIKE '%rehabil%'
             OR discharge_location LIKE '%ltach%'
             OR discharge_location LIKE '%long term%'
             OR discharge_location LIKE '%long-term%'
             OR discharge_location LIKE '%subacute%'
           )
        THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_outcome
  FROM cohort
)

SELECT
  discharge_outcome,
  COUNT(*) AS n,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- approximate quantiles (percentiles)
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS p50_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100.0 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_le_7_days
FROM
  classified
WHERE
  discharge_outcome IS NOT NULL
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;