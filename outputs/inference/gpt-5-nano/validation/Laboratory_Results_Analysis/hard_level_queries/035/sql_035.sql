with cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dd.long_title) LIKE '%ischemic%'
    AND LOWER(dd.long_title) LIKE '%stroke%'
),

-- 72-hour instability per cohort admission
cohort_instability AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    SUM(
      CASE
        WHEN le.valuenum IS NOT NULL
             AND le.ref_range_lower IS NOT NULL
             AND le.ref_range_upper IS NOT NULL
             AND le.charttime >= c.admittime
             AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
             AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        THEN 1
        ELSE 0
      END
    ) AS instability_72h
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = c.subject_id
   AND le.hadm_id = c.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

-- LOS (in days) for the cohort admissions
cohort_los AS (
  SELECT
    c.hadm_id,
    TIMESTAMP_DIFF(COALESCE(c.dischtime, c.admittime), c.admittime, SECOND) / 86400.0 AS los_days
  FROM cohort AS c
),

-- In-hospital mortality flag for the cohort admissions
cohort_mortality AS (
  SELECT
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM cohort
),

-- General inpatient instability per admission (for comparison group)
general_instability AS (
  SELECT
    a.hadm_id,
    SUM(
      CASE
        WHEN le.valuenum IS NOT NULL
             AND le.ref_range_lower IS NOT NULL
             AND le.ref_range_upper IS NOT NULL
             AND le.charttime >= a.admittime
             AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
             AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        THEN 1
        ELSE 0
      END
    ) AS instability_72h
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = a.subject_id
   AND le.hadm_id = a.hadm_id
  GROUP BY a.hadm_id
)

SELECT
  -- Minimum 72-hour lab instability across the specified cohort
  (SELECT MIN(instability_72h) FROM cohort_instability) AS min_72h_lab_instability,

  -- Average number of unstable labs in the 72h window for the cohort
  (SELECT AVG(instability_72h) FROM cohort_instability) AS cohort_avg_critical_events,

  -- Average number of unstable labs in the 72h window for all inpatients (general inpatient group)
  (SELECT AVG(instability_72h) FROM general_instability) AS general_inpatient_avg_critical_events,

  -- Cohort average length of stay (in days)
  (SELECT AVG(los_days) FROM cohort_los) AS cohort_avg_los_days,

  -- Cohort in-hospital mortality rate
  (SELECT AVG(mortality) FROM cohort_mortality) AS cohort_in_hosp_mortality_rate;