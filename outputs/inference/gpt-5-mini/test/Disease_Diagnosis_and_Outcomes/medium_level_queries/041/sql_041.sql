WITH
-- Admissions with any diagnosis whose description contains "sepsis"
sepsis_hadm AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%sepsis%'
),

-- Admissions that have any diagnosis whose description contains "septic shock" (to be excluded)
septic_shock_hadm AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%septic shock%'
),

-- Cohort: female patients age 50-60 (anchor_age), admissions with sepsis and without septic shock
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN sepsis_hadm s
    ON a.hadm_id = s.hadm_id
  LEFT JOIN septic_shock_hadm ss
    ON a.hadm_id = ss.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND ss.hadm_id IS NULL  -- exclude admissions with septic shock
),

-- Aggregated stats by LOS group
group_stats AS (
  SELECT
    CASE WHEN los_days <= 7 THEN 'LOS_<=7' ELSE 'LOS_>7' END AS los_group,
    COUNT(*) AS n_admissions,
    SUM(IF(hospital_expire_flag = 1, 1, 0)) AS n_deaths,
    100.0 * SAFE_DIVIDE(SUM(IF(hospital_expire_flag = 1, 1, 0)), COUNT(*)) AS mortality_pct,
    -- median time-to-death in days among in-hospital deaths (approximate median)
    APPROX_QUANTILES(
      CASE
        WHEN hospital_expire_flag = 1
         AND deathtime IS NOT NULL
         AND deathtime >= admittime
        THEN TIMESTAMP_DIFF(deathtime, admittime, SECOND) / 86400.0
        ELSE NULL
      END
      , 100
    )[OFFSET(50)] AS median_time_to_death_days
  FROM cohort
  GROUP BY los_group
)

-- Final output: two group rows plus a differences row
SELECT
  los_group,
  n_admissions,
  n_deaths,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(median_time_to_death_days, 2) AS median_time_to_death_days
FROM group_stats

UNION ALL

SELECT
  'Absolute_and_Relative_Differences' AS los_group,
  CAST(NULL AS INT64) AS n_admissions,
  CAST(NULL AS INT64) AS n_deaths,
  -- absolute difference: mortality(>7) - mortality(<=7) in percentage points
  ROUND(
    (
      MAX(CASE WHEN los_group = 'LOS_>7' THEN mortality_pct END)
      - MAX(CASE WHEN los_group = 'LOS_<=7' THEN mortality_pct END)
    )
  , 2) AS mortality_pct,
  -- relative difference in percent: (absolute / mortality(<=7)) * 100
  ROUND(
    100.0 * SAFE_DIVIDE(
      (MAX(CASE WHEN los_group = 'LOS_>7' THEN mortality_pct END)
       - MAX(CASE WHEN los_group = 'LOS_<=7' THEN mortality_pct END)
      ),
      MAX(CASE WHEN los_group = 'LOS_<=7' THEN mortality_pct END)
    )
  , 2) AS median_time_to_death_days

ORDER BY los_group DESC;