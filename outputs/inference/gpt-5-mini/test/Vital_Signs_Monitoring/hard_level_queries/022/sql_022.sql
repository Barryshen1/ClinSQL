WITH arf_hads AS (
  -- admissions/hadm_id with a diagnosis whose long_title mentions "acute respiratory failure"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),

cohort AS (
  -- icu stays for male patients aged 85-95 and admissions that have ARF
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
   AND s.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN arf_hads ar
    ON s.hadm_id = ar.hadm_id
  WHERE LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 85 AND 95
),

vitals_first24 AS (
  /*
    Pull charted vitals in first 24 hours of ICU stay.
    Identify common vital item types via d_items.label pattern matching.
  */
  SELECT
    c.stay_id,
    c.hadm_id,
    ce.subject_id,
    di.itemid,
    di.label,
    ce.charttime,
    ce.valuenum,
    -- classify into a canonical vital sign category
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' THEN 'hr'
      WHEN LOWER(di.label) LIKE '%pulse%' AND LOWER(di.label) LIKE '%rate%' THEN 'hr'
      WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN 'rr'
      WHEN LOWER(di.label) LIKE '%resp rate%' THEN 'rr'
      WHEN LOWER(di.label) LIKE '%systolic%' AND LOWER(di.label) LIKE '%pressure%' THEN 'sbp'
      WHEN (LOWER(di.label) LIKE '%abp systolic%' OR LOWER(di.label) LIKE '%art systolic%') THEN 'sbp'
      WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%oxy saturation%' OR LOWER(di.label) LIKE '%o2 sat%' THEN 'spo2'
      WHEN LOWER(di.label) LIKE '%temp%' OR LOWER(di.label) LIKE '%temperature%' THEN 'temp'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    -- keep only rows where our label matching detects a vital_type
    AND (
      LOWER(di.label) LIKE '%heart rate%' OR
      (LOWER(di.label) LIKE '%pulse%' AND LOWER(di.label) LIKE '%rate%') OR
      LOWER(di.label) LIKE '%respiratory rate%' OR
      LOWER(di.label) LIKE '%resp rate%' OR
      (LOWER(di.label) LIKE '%systolic%' AND LOWER(di.label) LIKE '%pressure%') OR
      LOWER(di.label) LIKE '%abp systolic%' OR
      LOWER(di.label) LIKE '%art systolic%' OR
      LOWER(di.label) LIKE '%spo2%' OR
      LOWER(di.label) LIKE '%oxygen saturation%' OR
      LOWER(di.label) LIKE '%o2 sat%' OR
      LOWER(di.label) LIKE '%temp%' OR
      LOWER(di.label) LIKE '%temperature%'
    )
),

vitals_flagged AS (
  -- Flag each vital measurement as unstable (1) or stable (0) using common clinical cutoffs.
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    vital_type,
    valuenum,
    charttime,
    CASE
      WHEN vital_type = 'hr'  AND (valuenum < 50 OR valuenum > 120) THEN 1
      WHEN vital_type = 'rr'  AND (valuenum < 8  OR valuenum > 30 ) THEN 1
      WHEN vital_type = 'sbp' AND (valuenum < 90 OR valuenum > 180) THEN 1
      WHEN vital_type = 'spo2' AND (valuenum < 90) THEN 1
      WHEN vital_type = 'temp' AND (valuenum < 35 OR valuenum > 39) THEN 1
      ELSE 0
    END AS unstable_flag
  FROM vitals_first24
),

per_stay_scores AS (
  -- Compute per-stay score: percentage of measurements that are unstable (0-100)
  SELECT
    v.stay_id,
    v.hadm_id,
    v.subject_id,
    COUNT(1) AS total_vitals_first24,
    SUM(unstable_flag) AS unstable_vitals_first24,
    100.0 * SAFE_DIVIDE(SUM(unstable_flag), COUNT(1)) AS instability_score,
    c.los,
    c.hospital_expire_flag
  FROM vitals_flagged v
  JOIN cohort c
    ON v.stay_id = c.stay_id
  GROUP BY v.stay_id, v.hadm_id, v.subject_id, c.los, c.hospital_expire_flag
),

-- compute the 75th percentile cutoff for the instability score distribution
quartile_cutoff AS (
  SELECT (APPROX_QUANTILES(instability_score, 4))[OFFSET(3)] AS q75
  FROM per_stay_scores
),

-- overall percentile rank of a score value (85) and summary of cohort
percentile_and_counts AS (
  SELECT
    COUNT(*) AS cohort_n,
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN instability_score <= 85 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_rank_of_85
  FROM per_stay_scores
),

-- stats for most unstable quartile (score >= 75th percentile cutoff)
top_quartile_stats AS (
  SELECT
    q.q75 AS cutoff_75,
    COUNT(*) AS top_quartile_n,
    AVG(p.los) AS avg_icu_los_top_quartile,
    AVG(p.hospital_expire_flag) AS inhospital_mortality_top_quartile
  FROM per_stay_scores p
  CROSS JOIN quartile_cutoff q
  WHERE p.instability_score >= q.q75
  GROUP BY q.q75
)

-- Final output: percentile rank of 85 and top-quartile stats
SELECT
  pc.percentile_rank_of_85,
  pc.cohort_n,
  t.cutoff_75,
  t.top_quartile_n,
  t.avg_icu_los_top_quartile,
  t.inhospital_mortality_top_quartile
FROM percentile_and_counts pc
CROSS JOIN top_quartile_stats t;