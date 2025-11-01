WITH stroke_hadm AS (
  -- Admissions for female patients age 78-88 with an ischemic stroke diagnosis
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
   AND dx.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dd.long_title) LIKE '%ischemic%'
    AND (LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%infarct%')
),

-- Per-admission counts of "critical" lab events within first 72 hours of admission
lab_crit_counts AS (
  SELECT
    a.hadm_id,
    COUNTIF(
      (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
      OR (
        le.flag IS NOT NULL
        AND (
          LOWER(le.flag) LIKE '%abnorm%'
          OR LOWER(le.flag) LIKE '%high%'
          OR LOWER(le.flag) LIKE '%low%'
          OR LOWER(le.flag) LIKE '%crit%'
        )
      )
    ) AS crit_events_72h
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

-- All admissions with basic metrics (LOS, expired flag) and left-joined lab counts
admission_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- compute LOS in days (fractional)
    CASE
      WHEN a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
      THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
      ELSE NULL
    END AS los_days,
    COALESCE(lc.crit_events_72h, 0) AS crit_events_72h
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN lab_crit_counts lc
    ON a.hadm_id = lc.hadm_id
)

-- Final aggregates: cohort stats and general inpatient comparison
SELECT
  -- Cohort identifiers and size
  COUNT(DISTINCT sh.hadm_id) AS cohort_n_admissions,

  -- Minimum 72-hour instability score within the cohort
  MIN(am_c.crit_events_72h) AS cohort_min_72h_instability_score,

  -- Cohort average critical events within 72h and general inpatients average for comparison
  ROUND(AVG(am_c.crit_events_72h), 3) AS cohort_avg_crit_events_72h,
  ROUND((
    SELECT AVG(crit_events_72h) FROM admission_metrics
  ), 3) AS general_inpatients_avg_crit_events_72h,

  -- Cohort LOS and in-hospital mortality
  ROUND(AVG(am_c.los_days), 3) AS cohort_avg_los_days,
  ROUND(AVG(CASE WHEN am_c.hospital_expire_flag IS NULL THEN 0 ELSE CAST(am_c.hospital_expire_flag AS NUMERIC) END), 4) AS cohort_in_hospital_mortality_rate

FROM stroke_hadm sh
JOIN admission_metrics am_c
  ON sh.hadm_id = am_c.hadm_id;