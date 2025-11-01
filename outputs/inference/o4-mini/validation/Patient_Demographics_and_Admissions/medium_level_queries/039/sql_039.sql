WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) IS NOT NULL
)
SELECT
  discharge_outcome,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- Approximate percentiles using APPROX_QUANTILES
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days,
  ROUND(100.0 * COUNTIF(los_days <= 7) / COUNT(*), 2) AS pct_rank_7day
FROM
  filtered_admissions
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;