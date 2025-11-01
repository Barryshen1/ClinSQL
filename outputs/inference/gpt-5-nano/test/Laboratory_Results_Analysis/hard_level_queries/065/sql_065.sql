WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_icd
    ON a.subject_id = d_icd.subject_id AND a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE (p.gender = 'F' OR LOWER(p.gender) = 'female')
    AND p.anchor_age BETWEEN 65 AND 75
    AND (
      LOWER(d.long_title) LIKE '%lower gi%' OR
      LOWER(d.long_title) LIKE '%lower gastrointestinal%' OR
      LOWER(d.long_title) LIKE '%gastrointestinal hemorrhage%'
    )
),

lab_events AS (
  -- Labs within 72 hours for the cohort
  SELECT
    c.subject_id,
    c.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = c.subject_id
   AND l.hadm_id = c.hadm_id
   AND l.charttime >= c.admittime
   AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),

lab_stats AS (
  -- abnormal_count per admission and total_lab_events in the 72h window
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
          WHEN (valuenum IS NOT NULL
                AND ((ref_range_lower IS NOT NULL AND valuenum < ref_range_lower)
                     OR (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)))
               OR (flag IS NOT NULL AND LOWER(flag) IN ('h','high','c','critical'))
          THEN 1
          ELSE 0
        END) AS abnormal_count,
    COUNT(*) AS total_lab_events
  FROM lab_events
  GROUP BY subject_id, hadm_id
),

instability AS (
  -- per-admission instability score
  SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(ls.abnormal_count, 0) AS instability_score
  FROM cohort AS c
  LEFT JOIN lab_stats AS ls
    ON c.subject_id = ls.subject_id
   AND c.hadm_id = ls.hadm_id
),

lab_events_cohort AS (
  -- for critical rate: per admission, count of critical labs and total labs
  SELECT
    c.subject_id,
    c.hadm_id,
    SUM(CASE WHEN (l.flag IS NOT NULL AND LOWER(l.flag) IN ('h','high','c','critical')) THEN 1 ELSE 0 END) AS critical_lab_events,
    COUNT(*) AS total_lab_events
  FROM cohort AS c
  LEFT JOIN lab_events AS l
    ON l.subject_id = c.subject_id
   AND l.hadm_id = c.hadm_id
   AND l.charttime >= c.admittime
   AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

cohort_critical_rate AS (
  -- cohort critical rate
  SELECT SUM(critical_lab_events) / NULLIF(SUM(total_lab_events), 0) AS critical_rate
  FROM lab_events_cohort
),

general_lab_events AS (
  -- all admissions in hosp with labs in first 72h (general inpatient baseline)
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = a.subject_id
   AND l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

general_lab_events_crit AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE WHEN (flag IS NOT NULL AND LOWER(flag) IN ('h','high','c','critical')) THEN 1 ELSE 0 END) AS critical_lab_events,
    COUNT(*) AS total_lab_events
  FROM general_lab_events
  GROUP BY subject_id, hadm_id
),

general_critical_rate AS (
  -- general inpatient critical rate
  SELECT SUM(critical_lab_events) / NULLIF(SUM(total_lab_events), 0) AS critical_rate
  FROM general_lab_events_crit
),

cohort_los AS (
  SELECT
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS cohort_avg_los_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS cohort_mortality_rate
  FROM cohort
),

percentile AS (
  -- 25th percentile of instability_score using APPROX_QUANTILES (BigQuery standard SQL)
  SELECT APPROX_QUANTILES(instability_score, 4) AS q
  FROM instability
)

-- Final output: 25th percentile instability, cohort vs general critical rates, LOS, mortality
SELECT
  percentile.q[OFFSET(1)] AS instability_25th_percentile,
  (SELECT critical_rate FROM cohort_critical_rate) AS cohort_critical_rate,
  (SELECT critical_rate FROM general_critical_rate) AS general_critical_rate,
  (SELECT cohort_avg_los_days FROM cohort_los) AS cohort_avg_los_days,
  (SELECT cohort_mortality_rate FROM cohort_los) AS cohort_mortality_rate
FROM percentile;