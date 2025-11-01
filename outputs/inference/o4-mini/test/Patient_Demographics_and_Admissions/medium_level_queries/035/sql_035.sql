WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Compute LOS in days as a float
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los,
    -- Define discharge outcome
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND UPPER(a.admission_location) LIKE '%ED%'
),
quartiles AS (
  SELECT
    outcome,
    -- Compute quartiles: offsets 0=min,1=Q1,2=median,3=Q3,4=max
    APPROX_QUANTILES(los, 4) AS q_array
  FROM cohort
  GROUP BY outcome
)
SELECT
  q.outcome,
  -- Median = element at offset 2
  q.q_array[OFFSET(2)] AS median_los_days,
  -- IQR = Q3 (offset 3) minus Q1 (offset 1)
  q.q_array[OFFSET(3)] - q.q_array[OFFSET(1)] AS iqr_los_days,
  -- Percentile rank of a 14-day stay = proportion of stays ≤ 14 days
  SUM(CASE WHEN c.los <= 14 THEN 1 ELSE 0 END) / COUNT(*) AS pct_leq_14d
FROM 
  quartiles q
JOIN
  cohort c
ON
  q.outcome = c.outcome
GROUP BY
  q.outcome,
  q.q_array
ORDER BY
  q.outcome;