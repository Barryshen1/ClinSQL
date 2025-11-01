WITH med_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.services` AS s
      ON a.subject_id = s.subject_id
     AND a.hadm_id    = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND s.curr_service = 'MEDICINE'
),
cohort AS (
  SELECT
    hadm_id,
    -- LOS in days
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS outcome
  FROM
    med_admissions
),
stats AS (
  SELECT
    outcome,
    -- Mean LOS
    AVG(los) AS mean_los,
    -- Quantile array (0th,1st,…,100th percentiles)
    APPROX_QUANTILES(los, 100) AS quantiles,
    -- count LOS ≤10
    SUM(IF(los <= 10, 1, 0)) AS cnt_le_10,
    COUNT(*) AS total_count
  FROM
    cohort
  GROUP BY
    outcome
)
SELECT
  outcome,
  mean_los,
  quantiles[OFFSET(25)]  AS p25_los,
  quantiles[OFFSET(50)]  AS p50_los,
  quantiles[OFFSET(75)]  AS p75_los,
  quantiles[OFFSET(90)]  AS p90_los,
  100.0 * cnt_le_10 / total_count AS pct_los_le_10
FROM
  stats
ORDER BY
  outcome;