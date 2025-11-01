WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY ROOM'
),

discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN discharge_location IN (
        ' skilled NURSING FACILITY', 'REHAB', 'LONG TERM CARE HOSPITAL',
        'HOSPICE', 'AGAINST ADVICE', 'PSYCH FACILITY'
      ) THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    cohort
  WHERE
    discharge_location IS NOT NULL
),

stats AS (
  SELECT
    discharge_outcome,
    APPROX_QUANTILES(los, 4) AS quartiles,
    COUNT(*) AS n
  FROM
    discharge_groups
  GROUP BY
    discharge_outcome
),

percentile_ranks AS (
  SELECT
    discharge_outcome,
    los,
    PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los) AS pct_rank
  FROM
    discharge_groups
),

pct_14_days AS (
  SELECT
    discharge_outcome,
    MAX(CASE WHEN los <= 14 THEN pct_rank ELSE NULL END) AS pct_rank_14
  FROM
    percentile_ranks
  GROUP BY
    discharge_outcome
)

SELECT
  s.discharge_outcome,
  ROUND(s.quartiles[ORDINAL(3)], 2) AS median_los,
  ROUND(s.quartiles[ORDINAL(4)] - s.quartiles[ORDINAL(2)], 2) AS los_iqr,
  ROUND(p.pct_rank_14 * 100, 2) AS percentile_rank_14_days
FROM
  stats s
JOIN
  pct_14_days p
ON
  s.discharge_outcome = p.discharge_outcome
ORDER BY
  s.discharge_outcome;