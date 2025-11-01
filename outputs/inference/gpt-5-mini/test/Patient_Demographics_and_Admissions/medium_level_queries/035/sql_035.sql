WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_location,
    a.edregtime,
    -- fractional LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- admitted from ED: prefer edregtime, also match common "emerg" text in admission_location
    AND (a.edregtime IS NOT NULL OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emerg%')
),

cohort_outcome AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE 'home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome
  FROM cohort
),

agg AS (
  SELECT
    discharge_outcome,
    COUNT(*) AS n,
    SUM(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) AS n_lte14,
    ARRAY_AGG(los_days ORDER BY los_days) AS los_array
  FROM cohort_outcome
  GROUP BY discharge_outcome
)

SELECT
  discharge_outcome,
  n AS admissions_count,
  -- Q1
  los_array[OFFSET(CAST(FLOOR((n - 1) * 0.25) AS INT64))] AS q1_days,
  -- Median (handle odd/even n)
  CASE
    WHEN n = 0 THEN NULL
    WHEN MOD(n, 2) = 1 THEN los_array[OFFSET(CAST((n - 1) / 2 AS INT64))]
    ELSE (
      (los_array[OFFSET(CAST(n / 2 - 1 AS INT64))] +
       los_array[OFFSET(CAST(n / 2 AS INT64))]) / 2.0
    )
  END AS median_days,
  -- Q3
  los_array[OFFSET(CAST(FLOOR((n - 1) * 0.75) AS INT64))] AS q3_days,
  -- IQR = Q3 - Q1
  los_array[OFFSET(CAST(FLOOR((n - 1) * 0.75) AS INT64))] -
    los_array[OFFSET(CAST(FLOOR((n - 1) * 0.25) AS INT64))] AS iqr_days,
  -- Percentile rank of a 14-day stay = percent of admissions with LOS <= 14 days
  SAFE_MULTIPLY(100.0, SAFE_DIVIDE(n_lte14, n)) AS pct_rank_14day
FROM agg
ORDER BY
  -- present death last or first; choose alphabetic
  discharge_outcome;