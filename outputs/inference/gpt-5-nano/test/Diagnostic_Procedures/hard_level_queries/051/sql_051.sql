WITH cohort_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = icu.subject_id
   AND di.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 90 AND 100
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
cohort_with_death AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.los, s.deathtime
  FROM cohort_stays s
),
lab_counts AS (
  SELECT c.stay_id,
         COUNT(le.labevent_id) AS diagnostic_count
  FROM cohort_with_death c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = c.subject_id
   AND le.hadm_id = c.hadm_id
   AND le.charttime >= c.intime
   AND le.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),
per_stay AS (
  SELECT w.subject_id, w.hadm_id, w.stay_id, w.intime, w.los, w.deathtime,
         COALESCE(lc.diagnostic_count, 0) AS diagnostic_count
  FROM cohort_with_death w
  LEFT JOIN lab_counts lc ON lc.stay_id = w.stay_id
),
totals AS (
  SELECT COUNT(*) AS total_icustays
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
mort_and_los AS (
  SELECT
    100.0 * SUM(CASE WHEN pw.deathtime IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_percent,
    AVG(pw.los) AS avg_los_icustay_hours,
    COUNT(*) AS admissions_cohort
  FROM per_stay pw
),
stats AS (
  SELECT STDDEV_SAMP(diagnostic_count) AS sd_diagnostic_first24h,
         APPROX_QUANTILES(diagnostic_count, 100) AS quantiles
  FROM per_stay
),
final AS (
  SELECT
    s.sd_diagnostic_first24h,
    s.quantiles[OFFSET(75)] AS p75_diagnostic_first24h,
    s.quantiles[OFFSET(95)] AS p95_diagnostic_first24h,
    m.in_hospital_mortality_percent,
    m.avg_los_icustay_hours,
    m.admissions_cohort,
    t.total_icustays,
    100.0 * m.admissions_cohort / t.total_icustays AS admissions_ratio_percent
  FROM stats s
  CROSS JOIN mort_and_los m
  CROSS JOIN totals t
)
SELECT * FROM final;