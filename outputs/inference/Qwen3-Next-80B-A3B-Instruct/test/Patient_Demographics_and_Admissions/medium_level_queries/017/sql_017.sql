WITH icu_los AS (
  SELECT
    p.gender,
    p.anchor_age,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Calculate LOS in days
    DATETIME_DIFF(i.outtime, i.intime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND i.intime IS NOT NULL
    AND i.outtime IS NOT NULL
),
classified AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOME%' OR discharge_location LIKE '%DISCHARGE TO HOME%' THEN 'Home'
      WHEN discharge_location LIKE '%FACILITY%' 
        OR discharge_location LIKE '%REHAB%' 
        OR discharge_location LIKE '%SNF%' 
        OR discharge_location LIKE '%NURSING HOME%' 
        OR discharge_location LIKE '%LONG TERM CARE%' 
        OR discharge_location LIKE '%EXTENDED CARE%' 
        OR discharge_location LIKE '%SKILLED NURSING%' THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM
    icu_los
  WHERE
    discharge_location IS NOT NULL OR hospital_expire_flag = 1
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(500)] AS median_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] AS p75_los_days,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(900)] AS p90_los_days
FROM
  classified
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;