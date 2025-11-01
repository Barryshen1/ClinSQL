WITH
-- 1) Identify admissions with ischemic-stroke diagnoses (text-match on diagnosis description).
stroke_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ischemi%'
     OR LOWER(d.long_title) LIKE '%infarct%'
     OR LOWER(d.long_title) LIKE '%cerebral infarction%'
),

-- 2) Define cohort: ICU stays for male patients aged 84-94 with an admission containing ischemic stroke
cohort_icustays AS (
  SELECT s.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN stroke_admissions sa
    ON s.hadm_id = sa.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- 3) Extract relevant vital sign events in first 72 hours, mapping item labels to vital types via d_items text matching
vital_events AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.charttime,
    di.label AS item_label,
    ce.valuenum,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'heart.? ?rate|(^|\W)hr(\W|$)') THEN 'hr'
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'respiratory.? ?rate|(^|\W)rr(\W|$)') THEN 'rr'
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'systolic') THEN 'sbp'
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'temp|temperature') THEN 'temp'
      WHEN REGEXP_CONTAINS(LOWER(di.label), r'spo2|oxygen.? ?saturat|o2.? ?sat') THEN 'spo2'
      ELSE NULL
    END AS vital_type,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort_icustays i
    ON ce.subject_id = i.subject_id
    AND ce.hadm_id = i.hadm_id
    AND ce.stay_id = i.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
),

-- 4) Keep only rows where the item label matched one of the vital types
vital_events_filtered AS (
  SELECT *,
    SAFE_CAST(valuenum AS FLOAT64) AS val
  FROM vital_events
  WHERE vital_type IS NOT NULL
),

-- 5) Flag abnormal measurements based on thresholds
vital_abnormals AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    vital_type,
    val,
    intime,
    CASE
      WHEN vital_type = 'hr'  AND (val > 120 OR val < 40) THEN 1
      WHEN vital_type = 'rr'  AND (val > 30  OR val < 8)  THEN 1
      WHEN vital_type = 'sbp' AND (val > 180 OR val < 90) THEN 1
      WHEN vital_type = 'temp' AND (val > 38.5 OR val < 36) THEN 1
      WHEN vital_type = 'spo2' AND (val < 90)               THEN 1
      ELSE 0
    END AS is_abnormal,
    CAST(FLOOR(TIMESTAMP_DIFF(charttime, intime, MINUTE) / 60) AS INT64) AS hour_bin
  FROM vital_events_filtered
  WHERE SAFE_CAST(valuenum AS FLOAT64) IS NOT NULL
),

-- 6) For each stay and hour_bin, determine if that hour is abnormal (any abnormal vital recorded in that hour)
abnormal_hour_flags AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    hour_bin,
    MAX(is_abnormal) AS hour_abnormal
  FROM vital_abnormals
  WHERE hour_bin BETWEEN 0 AND 71
  GROUP BY stay_id, subject_id, hadm_id, hour_bin
),

-- 7) For each stay compute the instability score = 100 * (# abnormal hours / 72)
instability_scores AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    COALESCE(SUM(ah.hour_abnormal), 0) AS abnormal_hours,
    72 AS total_hours,
    100.0 * COALESCE(SUM(ah.hour_abnormal), 0) / 72.0 AS instability_score
  FROM cohort_icustays s
  LEFT JOIN abnormal_hour_flags ah
    ON s.stay_id = ah.stay_id
  GROUP BY s.stay_id, s.subject_id, s.hadm_id
),

-- 8) Attach LOS and mortality info
scores_with_outcomes AS (
  SELECT
    iscores.*,
    icu.los,
    adm.hospital_expire_flag
  FROM instability_scores iscores
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON iscores.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON iscores.hadm_id = adm.hadm_id
),

-- 9) Compute approximate quantiles for instability_score once
quantiles_scores AS (
  SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
  FROM scores_with_outcomes
)

-- Final aggregates: percentile of 80, and top-quartile outcomes
SELECT
  -- cohort size
  COUNT(*) AS cohort_size,
  -- percentile position of score = 80 (percentage of stays with score <= 80)
  100.0 * SUM(CASE WHEN instability_score <= 80 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_score_80,
  -- approx 75th percentile threshold
  (SELECT quantiles[OFFSET(75)] FROM quantiles_scores) AS approx_75th_percentile_score,
  -- metrics for top quartile (score >= approx 75th percentile)
  (SELECT COUNT(*) FROM scores_with_outcomes s2
     WHERE s2.instability_score >= (SELECT quantiles[OFFSET(75)] FROM quantiles_scores)
  ) AS top_quartile_count,
  -- mean LOS for top quartile (days)
  (SELECT AVG(s2.los) FROM scores_with_outcomes s2
     WHERE s2.instability_score >= (SELECT quantiles[OFFSET(75)] FROM quantiles_scores)
  ) AS top_quartile_mean_los_days,
  -- median LOS for top quartile (approx)
  (SELECT quantiles2[OFFSET(1)]
   FROM (
     SELECT APPROX_QUANTILES(los, 2) AS quantiles2
     FROM scores_with_outcomes s3
     WHERE s3.instability_score >= (SELECT quantiles[OFFSET(75)] FROM quantiles_scores)
   )
  ) AS top_quartile_median_los_days,
  -- hospital mortality rate for top quartile (percent)
  (SELECT 100.0 * SUM(CASE WHEN s2.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)
     FROM scores_with_outcomes s2
     WHERE s2.instability_score >= (SELECT quantiles[OFFSET(75)] FROM quantiles_scores)
  ) AS top_quartile_hospital_mortality_percent
FROM scores_with_outcomes s1;