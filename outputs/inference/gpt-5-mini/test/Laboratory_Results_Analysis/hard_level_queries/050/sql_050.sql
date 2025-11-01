WITH
-- 1) Female patients aged 40-50
patients_f AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- 2) Admissions for that subset
admissions_cohort AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patients_f p USING(subject_id)
),

-- 3) Identify ARDS diagnoses (match by d_icd_diagnoses.long_title or common ICD codes)
diagnoses_ards AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
      LOWER(COALESCE(d.long_title, '')) LIKE '%acute respiratory distress%'
      OR di.icd_code IN ('J80', '518.82', '51882')
      OR REPLACE(di.icd_code, '.', '') IN ('J80', '51882')
    )
),

-- 4) Lab critical counts in first 72 hours for admissions in the cohort
lab_crit_counts AS (
  SELECT
    a.hadm_id,
    COUNT(*) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN admissions_cohort a
    ON l.hadm_id = a.hadm_id
   AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE
    (
      (l.valuenum IS NOT NULL
       AND (
         (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
         OR
         (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
       )
      )
      OR (l.flag IS NOT NULL AND TRIM(l.flag) <> '')
    )
  GROUP BY a.hadm_id
),

-- 5) Per-admission scores (include admissions with zero critical events)
admission_scores AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag,
    SAFE_DIVIDE(CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) AS FLOAT64), 86400.0) AS los_days,
    COALESCE(l.critical_count, 0) AS score
  FROM admissions_cohort a
  LEFT JOIN lab_crit_counts l
    ON a.hadm_id = l.hadm_id
),

-- 6) ARDS admission scores and non-ARDS admission scores
ards_scores AS (
  SELECT s.*
  FROM admission_scores s
  WHERE s.hadm_id IN (SELECT hadm_id FROM diagnoses_ards)
),
nonards_scores AS (
  SELECT s.*
  FROM admission_scores s
  WHERE s.hadm_id NOT IN (SELECT hadm_id FROM diagnoses_ards)
),

-- 7) 75th percentile threshold among ARDS admission scores
ards_threshold AS (
  SELECT
    COALESCE(
      (SELECT APPROX_QUANTILES(score, 100)[OFFSET(75)] FROM ards_scores),
      0
    ) AS threshold_75
),

-- 8) Aggregates for ARDS admissions at/above threshold
ards_agg AS (
  SELECT
    COUNT(*) AS ards_high_n,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS ards_high_mortality_rate,
    AVG(los_days) AS ards_high_mean_los_days,
    AVG(score) AS ards_high_avg_critical_events_per_patient
  FROM ards_scores s
  JOIN ards_threshold t ON TRUE
  WHERE s.score >= t.threshold_75
),

-- 9) Aggregates for non-ARDS admissions (age-matched cohort)
nonards_agg AS (
  SELECT
    COUNT(*) AS nonards_n,
    AVG(score) AS nonards_avg_critical_events_per_patient
  FROM nonards_scores
)

-- Final aggregated results:
SELECT
  t.threshold_75 AS ards_75th_score_threshold,
  a.ards_high_n,
  a.ards_high_mortality_rate,
  a.ards_high_mean_los_days,
  a.ards_high_avg_critical_events_per_patient,
  n.nonards_avg_critical_events_per_patient,
  n.nonards_n
FROM ards_threshold t
LEFT JOIN ards_agg a ON TRUE
LEFT JOIN nonards_agg n ON TRUE;