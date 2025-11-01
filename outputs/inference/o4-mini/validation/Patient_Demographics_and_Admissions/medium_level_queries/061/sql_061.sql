WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    a.hospital_expire_flag,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'MEDICARE'
),
classified AS (
  SELECT
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE 'HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_outcome
  FROM filtered_admissions
)
SELECT
  discharge_outcome,
  n_stays,
  ROUND(avg_los, 2) AS mean_los,
  quantiles[OFFSET(50)] AS median_los,
  quantiles[OFFSET(75)] AS p75_los,
  quantiles[OFFSET(90)] AS p90_los,
  ROUND(100.0 * cnt_le_10_days / n_stays, 2) AS pct_le_10_days
FROM (
  SELECT
    discharge_outcome,
    COUNT(*) AS n_stays,
    AVG(los) AS avg_los,
    APPROX_QUANTILES(los, 100) AS quantiles,
    SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) AS cnt_le_10_days
  FROM classified
  GROUP BY discharge_outcome
)
ORDER BY discharge_outcome;