WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) AS los_sec,
    -- Discharge outcome category
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%snf%' OR
           LOWER(a.discharge_location) LIKE '%rehab%' OR
           LOWER(a.discharge_location) LIKE '%ltac%' THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE UPPER(a.admission_type) = 'ELECTIVE'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
    AND LOWER(p.gender) IN ('m','male')
    AND a.dischtime IS NOT NULL
)
, calc AS (
  SELECT
    discharge_outcome,
    los_sec / 86400.0 AS los_days
  FROM cohort
  WHERE discharge_outcome IS NOT NULL
)
SELECT
  discharge_outcome,
  AVG(los_days) AS mean_los_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(50)] AS p50_los_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(75)] AS p75_los_days,
  (APPROX_QUANTILES(los_days, 100))[OFFSET(90)] AS p90_los_days,
  100 * SUM(CASE WHEN los_days <= 7.0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_le_7
FROM calc
GROUP BY discharge_outcome
HAVING discharge_outcome IS NOT NULL
ORDER BY discharge_outcome;