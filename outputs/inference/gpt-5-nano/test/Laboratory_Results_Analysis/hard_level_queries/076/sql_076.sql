WITH
-- ACS cohort: male, age 87-97, with ACS (based on long_title of myocardial/unstable/acute coronary)
acs_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      LOWER(d.long_title) LIKE '%myocardial%'
      OR LOWER(d.long_title) LIKE '%unstable%'
      OR LOWER(d.long_title) LIKE '%acute coronary%'
    )
),

-- General inpatient cohort for comparator: male, age 87-97 (ACS-agnostic)
general_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

-- 72-hour instability score per ACS admission: stddev of valuenum from labs in first 72h
instability AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag,
         STDDEV_SAMP(l.valuenum) AS instability_score
  FROM acs_cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = c.subject_id
   AND l.hadm_id = c.hadm_id
   AND l.charttime >= c.admittime
   AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
   AND l.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

-- 95th percentile of instability scores (approximate quantiles)
p95 AS (
  SELECT quantiles[OFFSET(94)] AS p95
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
    FROM instability
    WHERE instability_score IS NOT NULL
  )
),

-- Admissions in ACS cohort with instability score >= 95th percentile
p95_group AS (
  SELECT i.subject_id, i.hadm_id, i.admittime, i.dischtime, i.hospital_expire_flag, i.instability_score
  FROM instability AS i
  CROSS JOIN p95
  WHERE i.instability_score >= p95.p95
),

-- LOS for P95 group (in days)
p95_los AS (
  SELECT g.hadm_id, g.subject_id,
         TIMESTAMP_DIFF(g.dischtime, g.admittime, SECOND) / 86400.0 AS los_days,
         g.hospital_expire_flag AS mortality
  FROM p95_group AS g
),

-- Critical lab events per admission for P95 group (labs outside ref ranges within 72h)
p95_crit AS (
  SELECT g.hadm_id, COUNT(*) AS crit_events
  FROM p95_group AS g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = g.subject_id
   AND l.hadm_id = g.hadm_id
   AND l.charttime >= g.admittime
   AND l.charttime <= TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
   AND l.valuenum IS NOT NULL
  WHERE (
        (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
     OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
  )
  GROUP BY g.hadm_id
),

-- Critical lab events per admission for general inpatients (ACS-agnostic)
general_crit_counts AS (
  SELECT a.hadm_id, COUNT(*) AS crit_events
  FROM general_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = a.subject_id
   AND l.hadm_id = a.hadm_id
   AND l.charttime >= a.admittime
   AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
   AND l.valuenum IS NOT NULL
  WHERE (
        (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
     OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
  )
  GROUP BY a.hadm_id
)

-- Final summary: P95 threshold, P95 group LOS and mortality, P95 vs general on avg critical lab events
SELECT
  (SELECT p95.p95 FROM p95 LIMIT 1) AS p95_threshold,
  (SELECT AVG(los_days) FROM p95_los) AS p95_mean_los_days,
  (SELECT AVG(mortality) FROM p95_los) AS p95_mortality_rate,
  (SELECT AVG(crit_events) FROM p95_crit) AS p95_avg_crit_events,
  (SELECT AVG(crit_events) FROM general_crit_counts) AS general_avg_crit_events,
  (SELECT AVG(crit_events) FROM p95_crit) - (SELECT AVG(crit_events) FROM general_crit_counts) AS diff_avg_crit_events
;