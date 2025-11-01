WITH
-- Identify RR-related itemids from d_items (ICU module)
rr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respir%'    -- catches "Respiratory Rate", "Resp Rate", etc.
),

-- Cohort: female patients aged 41-51 (anchor_age)
cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

-- ICU stays for cohort patients
cohort_icustays AS (
  SELECT s.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN cohort_patients p USING (subject_id)
),

-- RR events from chartevents within first 48 hours of ICU stay
rr_chartevents AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id, c.charttime, c.itemid, c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN cohort_icustays icu
    ON c.subject_id = icu.subject_id
   AND c.stay_id = icu.stay_id
  JOIN rr_itemids r ON c.itemid = r.itemid
  WHERE c.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 120
),

-- Unioned RR events (only from chartevents; datetimesevents not available in this dataset)
rr_events AS (
  SELECT subject_id, hadm_id, stay_id, charttime, valuenum
  FROM rr_chartevents
),

-- Per-stay average RR in first 48 hours (only stays with at least one RR measurement)
per_stay_avg_rr AS (
  SELECT
    re.subject_id,
    re.hadm_id,
    re.stay_id,
    AVG(re.valuenum) AS avg_rr,
    COUNT(*) AS rr_measure_count
  FROM rr_events re
  GROUP BY re.subject_id, re.hadm_id, re.stay_id
),

-- Identify admissions (hadm_id) with a stroke diagnosis using diagnosis text
stroke_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE (
        LOWER(COALESCE(dd.long_title, '')) LIKE '%stroke%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cerebrovasc%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cerebral infarct%'
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%cerebrovascular%'
  )
),

-- Combine per-stay averages with cohort icustays to ensure we only include cohort stays,
-- and mark stroke flag based on hadm_id
stays_with_rr_and_stroke AS (
  SELECT
    pstay.subject_id,
    pstay.hadm_id,
    pstay.stay_id,
    pstay.avg_rr,
    pstay.rr_measure_count,
    CASE WHEN sh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS stroke_flag
  FROM per_stay_avg_rr pstay
  JOIN cohort_icustays icu
    ON pstay.stay_id = icu.stay_id
   AND pstay.subject_id = icu.subject_id
  LEFT JOIN stroke_hadm sh
    ON pstay.hadm_id = sh.hadm_id
)

-- Final aggregation: bucket avg_rr and compute counts and stroke rates
SELECT
  rr_bucket,
  COUNT(*) AS n_stays,
  SUM(stroke_flag) AS n_stroke,
  ROUND(100.0 * SAFE_DIVIDE(SUM(stroke_flag), COUNT(*)), 2) AS stroke_percent
FROM (
  SELECT
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
      WHEN avg_rr > 20 AND avg_rr < 30 THEN '21-29'
      ELSE '>=30'
    END AS rr_bucket,
    stroke_flag
  FROM stays_with_rr_and_stroke
)
GROUP BY rr_bucket
ORDER BY
  CASE rr_bucket
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
    ELSE 5
  END;