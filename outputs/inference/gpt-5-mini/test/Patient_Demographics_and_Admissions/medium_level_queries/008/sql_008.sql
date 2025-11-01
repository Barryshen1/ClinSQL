WITH medicine_admissions AS (
  -- Build cohort: female, age 52-62, non-elective, medicine inpatient, valid times
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    -- LOS in fractional days using TIMESTAMP_DIFF on converted DATETIME -> TIMESTAMP
    TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` s
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), SECOND) >= 0
    AND a.admission_type IS NOT NULL
    AND UPPER(a.admission_type) != 'ELECTIVE' -- non-elective
    -- medicine inpatient: match curr_service text containing 'MEDICIN' (covers 'MEDICINE', 'CARDIAC MEDICINE', etc.)
    AND UPPER(s.curr_service) LIKE '%MEDICIN%'
),

classified AS (
  -- Classify discharge into the three requested groups; death takes precedence
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    discharge_location,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'Home'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%nurs%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%rehab%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%skilled%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%facility%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%snf%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%ltc%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%assisted%'
        OR LOWER(COALESCE(discharge_location, '')) LIKE '%long term%'
      THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM medicine_admissions
)

SELECT
  discharge_category,
  n,
  ROUND(mean_los, 2) AS mean_los_days,
  ROUND(quantiles[OFFSET(50)], 2) AS p50_los_days,
  ROUND(quantiles[OFFSET(75)], 2) AS p75_los_days,
  ROUND(quantiles[OFFSET(90)], 2) AS p90_los_days,
  ROUND(100.0 * le7 / n, 2) AS pct_le_7_days
FROM (
  SELECT
    discharge_category,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100) AS quantiles, -- returns 0..100 percentiles
    SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) AS le7
  FROM classified
  WHERE discharge_category IS NOT NULL
  GROUP BY discharge_category
)
ORDER BY
  n DESC;