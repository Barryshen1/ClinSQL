WITH
-- 1. Cohort admissions with hemorrhagic stroke in men age 70–80
cohort_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
    AND LOWER(dd.long_title) LIKE '%stroke%'
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- 2. Compute first-48h lab instability scores for the cohort
cohort_scores AS (
  SELECT
    c.hadm_id,
    COUNTIF(
      -- unstable if numeric and outside ref range
      le.valuenum IS NOT NULL
      AND (
        (le.valuenum < le.ref_range_lower)
        OR (le.valuenum > le.ref_range_upper)
      )
    ) AS instability_score
  FROM
    cohort_adm c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON c.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

-- 3. Compute cohort summary metrics
cohort_summary AS (
  SELECT
    -- 25th percentile of instability scores
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS cohort_25pct_instability,
    -- mean LOS and mortality
    AVG(c.los_days) AS cohort_mean_LOS,
    AVG(c.hospital_expire_flag) AS cohort_mortality_rate
  FROM
    cohort_adm c
    LEFT JOIN cohort_scores s
      ON c.hadm_id = s.hadm_id
),

-- 4. General inpatient population
all_adm AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- 5. Compute first-48h lab instability for all inpatients
all_scores AS (
  SELECT
    aa.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND (
        le.valuenum < le.ref_range_lower
        OR le.valuenum > le.ref_range_upper
      )
    ) AS instability_events
  FROM
    all_adm aa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON aa.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 48 HOUR)
  GROUP BY aa.hadm_id
),

-- 6. General population summary
general_summary AS (
  SELECT
    -- critical-lab event rate = total instability events / total admissions
    SUM(instability_events) * 1.0 / COUNT(*) AS general_critical_lab_event_rate,
    AVG(aa.los_days) AS general_mean_LOS,
    AVG(aa.hospital_expire_flag) AS general_mortality_rate
  FROM
    all_adm aa
    LEFT JOIN all_scores s
      ON aa.hadm_id = s.hadm_id
)

-- Final output
SELECT
  cs.cohort_25pct_instability,
  gs.general_critical_lab_event_rate,
  cs.cohort_mean_LOS,
  cs.cohort_mortality_rate,
  gs.general_mean_LOS,
  gs.general_mortality_rate
FROM
  cohort_summary cs,
  general_summary gs;