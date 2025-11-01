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
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Discharge group assignment
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      ELSE NULL
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(a.admission_location) LIKE '%transfer from hospital%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  -- Percentiles
  APPROX_QUANTILES(los, 100)[25] AS los_25th,
  APPROX_QUANTILES(los, 100)[50] AS los_50th,
  APPROX_QUANTILES(los, 100)[75] AS los_75th,
  APPROX_QUANTILES(los, 100)[90] AS los_90th,
  -- Percent ≤10 days
  ROUND(100 * COUNTIF(los <= 10) / COUNT(*), 2) AS pct_los_le_10
FROM
  cohort
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;