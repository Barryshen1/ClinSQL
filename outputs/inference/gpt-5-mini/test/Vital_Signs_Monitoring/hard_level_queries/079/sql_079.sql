WITH
-- 1) Base ICU stays for older male patients (ages 81-91)
cohort_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- 2) HFNC events within first 48 hours (search across common ICU event tables)
hfnc_chartevents AS (
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    JOIN cohort_stays s
      ON ce.stay_id = s.stay_id
  WHERE
    ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%high flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%hfnc%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high-flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%highflow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high flow nasal%'
    )
),

hfnc_procedureevents AS (
  SELECT DISTINCT
    pe.subject_id,
    pe.hadm_id,
    pe.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON pe.itemid = di.itemid
    JOIN cohort_stays s
      ON pe.stay_id = s.stay_id
  WHERE
    pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%high flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%hfnc%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high-flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%highflow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high flow nasal%'
    )
),

hfnc_inputevents AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ie.itemid = di.itemid
    JOIN cohort_stays s
      ON ie.stay_id = s.stay_id
  WHERE
    ie.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%high flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%hfnc%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high-flow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%highflow%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%high flow nasal%'
    )
),

hfnc_stays AS (
  -- union HFNC evidence from multiple tables
  SELECT DISTINCT subject_id, hadm_id, stay_id FROM hfnc_chartevents
  UNION DISTINCT
  SELECT DISTINCT subject_id, hadm_id, stay_id FROM hfnc_procedureevents
  UNION DISTINCT
  SELECT DISTINCT subject_id, hadm_id, stay_id FROM hfnc_inputevents
),

-- 3) Composite instability score observations in first 48h (from chartevents, datetimeevents, and omr)
score_chartevents AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime AS obs_time,
    COALESCE(ce.valuenum, SAFE_CAST(ce.value AS FLOAT64)) AS score_val
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    JOIN cohort_stays s ON ce.stay_id = s.stay_id
  WHERE
    ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND LOWER(COALESCE(di.label, '')) LIKE '%instability%'
    AND (ce.valuenum IS NOT NULL OR SAFE_CAST(ce.value AS FLOAT64) IS NOT NULL)
),

score_datetimeevents AS (
  SELECT
    de.subject_id,
    de.hadm_id,
    de.stay_id,
    de.charttime AS obs_time,
    SAFE_CAST(de.value AS FLOAT64) AS score_val
  FROM
    `physionet-data.mimiciv_3_1_icu.datetimeevents` de
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON de.itemid = di.itemid
    JOIN cohort_stays s ON de.stay_id = s.stay_id
  WHERE
    de.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND LOWER(COALESCE(di.label, '')) LIKE '%instability%'
    AND SAFE_CAST(de.value AS FLOAT64) IS NOT NULL
),

score_omr AS (
  -- omr has chartdate (date) and result_value; match by date within intime +/- 2 days to approximate 48h
  SELECT
    o.subject_id,
    a.hadm_id,
    s.stay_id,
    TIMESTAMP(a.admittime) AS obs_time,  -- approximate timestamp using admittime
    SAFE_CAST(o.result_value AS FLOAT64) AS score_val
  FROM
    `physionet-data.mimiciv_3_1_hosp.omr` o
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN cohort_stays s
      ON a.hadm_id = s.hadm_id
  WHERE
    LOWER(o.result_name) LIKE '%instability%'
    AND SAFE_CAST(o.result_value AS FLOAT64) IS NOT NULL
    -- coarse date match: omr.chartdate within intime date +/- 2 days
    AND DATE(o.chartdate) BETWEEN DATE(s.intime) AND DATE(TIMESTAMP_ADD(s.intime, INTERVAL 2 DAY))
),

all_scores AS (
  SELECT * FROM score_chartevents
  UNION ALL
  SELECT * FROM score_datetimeevents
  UNION ALL
  SELECT * FROM score_omr
),

-- 4) First (earliest) instability score per stay within 48h
first_score_per_stay AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.los,
    sc.score_val,
    sc.obs_time,
    ROW_NUMBER() OVER (PARTITION BY s.stay_id ORDER BY sc.obs_time ASC) AS rn
  FROM
    cohort_stays s
    JOIN hfnc_stays h
      ON s.stay_id = h.stay_id
    JOIN all_scores sc
      ON sc.stay_id = s.stay_id
  WHERE
    sc.score_val IS NOT NULL
)
SELECT
  -- Part A: percentile rank of score = 85 among cohort (first-48h scores)
  ROUND(100.0 * SUM(CASE WHEN score_val <= 85 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_of_85,
  -- Part B: top decile outcomes (compute threshold then metrics)
  ROUND(top_decile_stats.avg_icu_los, 2) AS avg_icu_los_days,
  ROUND(100.0 * top_decile_stats.hospital_mortality_rate, 2) AS hospital_mortality_percent,
  top_decile_stats.top_decile_threshold AS score_90th_percentile_threshold,
  top_decile_stats.n_top_decile AS n_top_decile,
  top_decile_stats.n_cohort AS n_cohort
FROM (
  -- restrict to the earliest score per stay (rn = 1)
  SELECT *
  FROM first_score_per_stay
  WHERE rn = 1
) cohort_scores
CROSS JOIN (
  -- compute 90th percentile threshold and aggregated metrics for top decile
  SELECT
    APPROX_QUANTILES(score_val, 100)[OFFSET(90)] AS top_decile_threshold,
    -- compute stats for stays with score >= threshold
    AVG(CASE WHEN score_val >= APPROX_QUANTILES(score_val, 100)[OFFSET(90)] THEN los END) AS avg_icu_los,
    AVG(CASE WHEN score_val >= APPROX_QUANTILES(score_val, 100)[OFFSET(90)] THEN 1.0 * COALESCE(adm.hospital_expire_flag, 0) END) AS hospital_mortality_rate,
    SUM(CASE WHEN score_val >= APPROX_QUANTILES(score_val, 100)[OFFSET(90)] THEN 1 ELSE 0 END) AS n_top_decile,
    COUNT(*) AS n_cohort
  FROM (
    -- need stay-level rows with hadm for mortality join
    SELECT
      fs.stay_id,
      fs.score_val,
      fs.los,
      fs.hadm_id
    FROM (
      SELECT *
      FROM first_score_per_stay
      WHERE rn = 1
    ) fs
  ) x
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON x.hadm_id = adm.hadm_id
) AS top_decile_stats
;