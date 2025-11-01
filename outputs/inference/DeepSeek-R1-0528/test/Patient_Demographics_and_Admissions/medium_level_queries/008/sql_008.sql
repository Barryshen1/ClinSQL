WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_adm,
    -- Calculate LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN (
      -- Get initial service for each admission
      SELECT hadm_id, curr_service
      FROM `physionet-data.mimiciv_3_1_hosp.services`
      WHERE prev_service IS NULL
    ) s ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'F'
    AND a.admission_type != 'ELECTIVE'  -- Non-elective only
    AND s.curr_service = 'MEDICINE'     -- Initial service is Medicine
),
filtered_cohort AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME IV', 'HOME HEALTH CARE') THEN 'home'
      ELSE 'facility'
    END AS discharge_group,
    los_days
  FROM cohort
  WHERE age_adm BETWEEN 52 AND 62  -- Age filter
)
SELECT
  discharge_group,
  COUNT(*) AS n_patients,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  -- Percentile rank of 7 days: % of patients with LOS <= 7
  AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) * 100 AS pct_rank_7d
FROM filtered_cohort
GROUP BY discharge_group
ORDER BY discharge_group;