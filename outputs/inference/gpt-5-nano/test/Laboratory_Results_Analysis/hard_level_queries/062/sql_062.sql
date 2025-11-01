WITH
  -- Cohort: female, age 43-53
  cohort_base AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 43 AND 53
  ),
  -- Subset to those with sepsis (sepsis long_title in diagnoses)
  cohort_with_sepsis AS (
    SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.deathtime
    FROM cohort_base AS c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON c.hadm_id = di.hadm_id AND c.subject_id = di.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%sepsis%'
  ),
  -- Critical lab events within first 72 hours
  cohort_critical AS (
    SELECT h.hadm_id, COUNT(*) AS critical_count
    FROM cohort_with_sepsis AS h
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON h.hadm_id = l.hadm_id
     AND l.charttime >= h.admittime
     AND l.charttime < TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
     AND l.valuenum IS NOT NULL
     AND (l.flag IN ('H','L'))
    GROUP BY h.hadm_id
  ),
  -- Assemble per-admission metrics: critical_count, LOS, mortality
  cohort_agg AS (
    SELECT c.hadm_id,
           COALESCE(ce.critical_count, 0) AS critical_count,
           TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 3600.0 AS los_hours,
           CASE WHEN c.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
    FROM cohort_with_sepsis AS c
    LEFT JOIN cohort_critical AS ce
      ON c.hadm_id = ce.hadm_id
  ),
  -- Cohort summaries
  cohort_summaries AS (
    SELECT
      AVG(critical_count) AS cohort_mean_events,
      AVG(los_hours) AS cohort_mean_los_hours,
      AVG(mortality) AS cohort_mortality_rate
    FROM cohort_agg
  ),
  -- 25th percentile of instability (cohort)
  cohort_p25 AS (
    SELECT quantiles[OFFSET(25)] AS p25_instability
    FROM (
      SELECT APPROX_QUANTILES(critical_count, 100) AS quantiles
      FROM cohort_agg
    )
  ),

  -- General sepsis admissions (any age/sex)
  general_all AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%sepsis%'
  ),
  general_critical AS (
    SELECT g.hadm_id, COUNT(*) AS critical_count
    FROM general_all g
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON g.hadm_id = l.hadm_id
     AND l.charttime >= g.admittime
     AND l.charttime < TIMESTAMP_ADD(g.admittime, INTERVAL 72 HOUR)
     AND l.valuenum IS NOT NULL
     AND (l.flag IN ('H','L'))
    GROUP BY g.hadm_id
  ),
  general_agg AS (
    SELECT ga.hadm_id,
           COALESCE(gc.critical_count, 0) AS critical_count,
           TIMESTAMP_DIFF(ga.dischtime, ga.admittime, SECOND) / 3600.0 AS los_hours,
           CASE WHEN ga.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
    FROM general_all ga
    LEFT JOIN general_critical gc ON ga.hadm_id = gc.hadm_id
  ),
  general_summaries AS (
    SELECT
      AVG(critical_count) AS general_mean_events,
      AVG(los_hours) AS general_mean_los_hours,
      AVG(mortality) AS general_mortality_rate
    FROM general_agg
  )

SELECT
  'cohort_vs_general_summary' AS label,
  p25_instability,
  cohort_mean_events,
  cohort_mean_los_hours,
  cohort_mortality_rate,
  general_mean_events,
  general_mean_los_hours,
  general_mortality_rate
FROM cohort_p25
CROSS JOIN cohort_summaries
CROSS JOIN general_summaries;