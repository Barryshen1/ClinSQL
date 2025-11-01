WITH filtered_admissions AS (
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
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400) AS los_days,
    -- Discharge disposition
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS disposition
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  disposition,
  n_admissions,
  ROUND(quantiles[OFFSET(2)], 2) AS median_los_days,
  ROUND(quantiles[OFFSET(1)], 2) AS los_days_25th,
  ROUND(quantiles[OFFSET(3)], 2) AS los_days_75th,
  ROUND(quantiles[OFFSET(3)] - quantiles[OFFSET(1)], 2) AS iqr_los_days
FROM (
  SELECT
    disposition,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM
    filtered_admissions
  WHERE
    disposition IS NOT NULL
  GROUP BY
    disposition
)
ORDER BY
  disposition;