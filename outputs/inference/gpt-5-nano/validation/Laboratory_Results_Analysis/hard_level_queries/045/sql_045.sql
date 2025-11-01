WITH asthma_cohort AS (
  SELECT DISTINCT
         a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.deathtime,
         a.hospital_expire_flag,
         p.gender,
         p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(d.long_title) LIKE '%asthma%'
),

-- 72-hour instability per admission: stddev of lab values in first 72h
instability72h AS (
  SELECT
    ac.hadm_id,
    COALESCE(STDDEV_POP(lv.valuenum), 0) AS instability72h
  FROM asthma_cohort AS ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
    ON lv.hadm_id = ac.hadm_id
   AND lv.subject_id = ac.subject_id
   AND lv.charttime BETWEEN ac.admittime AND TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
  GROUP BY ac.hadm_id
),

scores AS (
  SELECT
    ac.hadm_id,
    COALESCE(i72.instability72h, 0) AS instability72h
  FROM asthma_cohort AS ac
  LEFT JOIN instability72h AS i72
    ON i72.hadm_id = ac.hadm_id
),

p90 AS (
  -- 90th percentile (approx) of instability72h across the cohort
  SELECT (q)[OFFSET(90)] AS p90
  FROM (
    SELECT APPROX_QUANTILES(instability72h, 100) AS q
    FROM scores
  )
),

top_hadm AS (
  SELECT s.hadm_id
  FROM scores s
  CROSS JOIN p90
  WHERE s.instability72h >= p90.p90
),

rest_hadm AS (
  SELECT s.hadm_id
  FROM scores s
  CROSS JOIN p90
  WHERE s.instability72h < p90.p90
),

-- Critical lab counts per admission within 72h (top decile)
crit_counts_top AS (
  SELECT a.hadm_id,
         SUM(CASE
               WHEN lv.valuenum IS NOT NULL
                 AND (
                       (lv.ref_range_lower IS NOT NULL AND lv.valuenum < lv.ref_range_lower) OR
                       (lv.ref_range_upper IS NOT NULL AND lv.valuenum > lv.ref_range_upper)
                     )
               THEN 1 ELSE 0
             END) AS count_critical
  FROM top_hadm t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = t.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
    ON lv.hadm_id = a.hadm_id
   AND lv.subject_id = a.subject_id
   AND lv.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

crit_counts_rest AS (
  SELECT a.hadm_id,
         SUM(CASE
               WHEN lv.valuenum IS NOT NULL
                 AND (
                       (lv.ref_range_lower IS NOT NULL AND lv.valuenum < lv.ref_range_lower) OR
                       (lv.ref_range_upper IS NOT NULL AND lv.valuenum > lv.ref_range_upper)
                     )
               THEN 1 ELSE 0
             END) AS count_critical
  FROM rest_hadm r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = r.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
    ON lv.hadm_id = a.hadm_id
   AND lv.subject_id = a.subject_id
   AND lv.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),

-- Top decile metrics
top_metrics AS (
  SELECT
     AVG(CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_top,
     AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_los_days_top,
     AVG(COALESCE(ct.count_critical, 0)) AS avg_crit_top
  FROM top_hadm t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = t.hadm_id
  LEFT JOIN crit_counts_top ct
    ON ct.hadm_id = a.hadm_id
),

-- Rest (age-matched) metrics
rest_metrics AS (
  SELECT
     AVG(CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rest,
     AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_los_days_rest,
     AVG(COALESCE(cr.count_critical, 0)) AS avg_crit_rest
  FROM rest_hadm r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = r.hadm_id
  LEFT JOIN crit_counts_rest cr
    ON cr.hadm_id = a.hadm_id
)

SELECT
  p90.p90 AS instability_90th_percentile,
  t.mortality_top AS mortality_top,
  t.mean_los_days_top AS mean_los_days_top,
  t.avg_crit_top AS avg_crit_top,
  r.mortality_rest AS mortality_rest,
  r.mean_los_days_rest AS mean_los_days_rest,
  r.avg_crit_rest AS avg_crit_rest,
  (t.mortality_top - r.mortality_rest) AS mortality_diff,
  (t.mean_los_days_top - r.mean_los_days_rest) AS los_days_diff,
  (t.avg_crit_top - r.avg_crit_rest) AS crit_events_diff
FROM p90
CROSS JOIN top_metrics t
CROSS JOIN rest_metrics r;