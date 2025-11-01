WITH cohorts AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE 'home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%facility%' 
           OR LOWER(a.discharge_location) LIKE '%rehabilitation%'
           OR LOWER(a.discharge_location) LIKE '%skilled%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome,
    -- LOS in days as decimal to capture partial days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE a.admission_type IN ('EMERGENCY', 'URGENT')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
mean_cte AS (
  SELECT
    discharge_outcome,
    AVG(los_days) AS mean_los_days
  FROM cohorts
  GROUP BY discharge_outcome
),
quant_cte AS (
  SELECT
    discharge_outcome,
    APPROX_QUANTILES(los_days, 100) AS q
  FROM cohorts
  GROUP BY discharge_outcome
)
SELECT
  m.discharge_outcome,
  m.mean_los_days,
  q.q[OFFSET(50)] AS median_los_days,
  q.q[OFFSET(75)] AS p75_los_days,
  q.q[OFFSET(90)] AS p90_los_days,
  q.q[OFFSET(10)] AS p10_los_days
FROM mean_cte AS m
JOIN quant_cte AS q
  ON m.discharge_outcome = q.discharge_outcome
ORDER BY discharge_outcome;