WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    -- compute LOS in days with fractional precision
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 60.0 / 24.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'home'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'hospice'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admission_type = 'EMERGENCY'
    -- keep only our three categories
    AND (
      a.hospital_expire_flag = 1
      OR UPPER(a.discharge_location) LIKE 'HOME%'
      OR UPPER(a.discharge_location) LIKE '%HOSPICE%'
    )
)
SELECT
  discharge_category,
  -- approximate quartiles: 0%,25%,50%,75%,100%
  quartiles[OFFSET(2)] AS median_los_days,
  -- IQR = Q3 - Q1
  quartiles[OFFSET(3)] - quartiles[OFFSET(1)] AS iqr_los_days
FROM (
  SELECT
    discharge_category,
    APPROX_QUANTILES(los_days, 4) AS quartiles
  FROM
    filtered_admissions
  GROUP BY
    discharge_category
)
ORDER BY
  discharge_category;