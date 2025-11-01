WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      ELSE 'Alive'
    END AS discharge_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` s
    ON s.subject_id = a.subject_id
   AND s.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- Age at admission: anchor_age + (admission_year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    -- Non-elective: EMERGENCY or URGENT
    AND a.admission_type IN ('EMERGENCY', 'URGENT')
    -- Medicine service
    AND LOWER(s.curr_service) LIKE '%medicine%'
    -- Basic sanity: non-null times and valid interval
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
ranked AS (
  SELECT
    discharge_status,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY discharge_status ORDER BY los_days) AS rn,
    COUNT(*) OVER (PARTITION BY discharge_status) AS total_per_status
  FROM cohort
)
SELECT
  discharge_status,
  AVG(los_days) AS mean_los_days,
  MAX(CASE WHEN rn = CAST(CEIL(total_per_status * 0.50) AS INT64) THEN los_days END) AS p50_los_days,
  MAX(CASE WHEN rn = CAST(CEIL(total_per_status * 0.75) AS INT64) THEN los_days END) AS p75_los_days,
  MAX(CASE WHEN rn = CAST(CEIL(total_per_status * 0.90) AS INT64) THEN los_days END) AS p90_los_days,
  100.0 * SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_5day
FROM ranked
GROUP BY discharge_status
ORDER BY discharge_status;