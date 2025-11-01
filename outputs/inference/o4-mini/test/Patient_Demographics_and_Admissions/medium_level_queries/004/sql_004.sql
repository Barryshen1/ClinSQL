WITH filt AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    -- compute age at admission
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    -- length of stay in days as a float
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 89 AND 99
    AND a.admission_type <> 'EMERGENCY'
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in_hospital_death'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'hospice'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'home'
      ELSE NULL
    END AS discharge_category
  FROM
    filt
)
SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los,
  -- median is the 50th percentile
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
  ROUND(100.0 * AVG(IF(los_days < 5, 1, 0)), 2) AS pct_los_lt_5
FROM
  categorized
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;