WITH
-- 1) Admissions that have diagnosis text matching common lower-GI bleed terms.
diag_match AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (
    LOWER(dd.long_title) LIKE '%divertic%'       -- diverticulosis/diverticulitis with hemorrhage
    OR LOWER(dd.long_title) LIKE '%angiodysplas%'-- angiodysplasia bleeding
    OR LOWER(dd.long_title) LIKE '%rectal%'       -- rectal bleeding
    OR LOWER(dd.long_title) LIKE '%rectum%'
    OR LOWER(dd.long_title) LIKE '%colon%'        -- colonic bleeding
    OR LOWER(dd.long_title) LIKE '%anal%'
    OR (
      LOWER(dd.long_title) LIKE '%gastrointestinal%' 
      AND (LOWER(dd.long_title) LIKE '%hemorrhag%' OR LOWER(dd.long_title) LIKE '%bleed%')
    )
    OR LOWER(dd.long_title) LIKE '%lower gastrointestinal%'
  )
),

-- 2) Cohort admissions: women age 65-75 with one of the diagnosis matches
cohort_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.hadm_id IN (SELECT hadm_id FROM diag_match)
),

-- 3) Aggregate critical lab counts within first 72 hours for cohort admissions
cohort_lab_agg AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort_adms ca
    ON le.hadm_id = ca.hadm_id
  WHERE le.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
    AND (
      -- a) explicit flag present (commonly H/L/abnormal)
      (le.flag IS NOT NULL AND TRIM(le.flag) != '')
      -- b) numeric value outside reference range
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
  GROUP BY ca.hadm_id
),

-- 4) Per-admission critical counts for the cohort, including zeros
cohort_counts AS (
  SELECT
    ca.hadm_id,
    COALESCE(cla.critical_count, 0) AS critical_count,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag
  FROM cohort_adms ca
  LEFT JOIN cohort_lab_agg cla
    ON ca.hadm_id = cla.hadm_id
),

-- 5) General adult admissions (comparison group)
general_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age >= 18
),

-- 6) Aggregate critical lab counts within first 72 hours for general admissions
general_lab_agg AS (
  SELECT
    ga.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN general_adms ga
    ON le.hadm_id = ga.hadm_id
  WHERE le.charttime BETWEEN ga.admittime AND TIMESTAMP_ADD(ga.admittime, INTERVAL 72 HOUR)
    AND (
      (le.flag IS NOT NULL AND TRIM(le.flag) != '')
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    )
  GROUP BY ga.hadm_id
),

-- 7) Per-admission critical counts for the general cohort, including zeros
general_counts AS (
  SELECT
    ga.hadm_id,
    COALESCE(gla.critical_count, 0) AS critical_count,
    ga.admittime,
    ga.dischtime,
    ga.hospital_expire_flag
  FROM general_adms ga
  LEFT JOIN general_lab_agg gla
    ON ga.hadm_id = gla.hadm_id
)

-- Final summary: cohort metrics, 25th percentile lab-instability score, compare to general inpatients,
-- LOS and mortality for the cohort.
SELECT
  -- Cohort basic counts
  (SELECT COUNT(*) FROM cohort_counts) AS cohort_n_admissions,

  -- 25th percentile of the lab-instability score (critical lab events in first 72h)
  (SELECT
     -- APPROX_QUANTILES returns an array of 101 quantiles when 100 buckets specified; OFFSET(25) ~ 25th percentile
     APPROX_QUANTILES(critical_count, 100)[OFFSET(25)]
   FROM cohort_counts
  ) AS cohort_25th_percentile_critical_lab_events_72h,

  -- Mean critical events in first 72h for cohort and general population (for comparison)
  (SELECT AVG(critical_count) FROM cohort_counts) AS cohort_mean_critical_events_72h,
  (SELECT AVG(critical_count) FROM general_counts) AS general_mean_critical_events_72h,

  -- Ratio (cohort mean / general mean), guarded against divide-by-zero
  SAFE_DIVIDE(
    (SELECT AVG(critical_count) FROM cohort_counts),
    NULLIF((SELECT AVG(critical_count) FROM general_counts), 0)
  ) AS mean_critical_event_rate_ratio_cohort_vs_general,

  -- Cohort LOS (days): median (approx) and mean
  (SELECT APPROX_QUANTILES(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 24.0), 100)[OFFSET(50)]
   FROM cohort_counts
   WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
  ) AS cohort_median_los_days_approx,
  (SELECT AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, HOUR), 24.0))
   FROM cohort_counts
   WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
  ) AS cohort_mean_los_days,

  -- Cohort in-hospital mortality proportion
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM cohort_counts) AS cohort_inhospital_mortality_proportion

;