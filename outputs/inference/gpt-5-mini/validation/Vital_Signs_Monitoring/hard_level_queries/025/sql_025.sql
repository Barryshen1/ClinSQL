WITH cohort_stays AS (
  -- ICU stays for male patients age 55-65 with any diagnosis containing "cardiac arrest"
  SELECT DISTINCT s.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(dd.long_title) LIKE '%cardiac arrest%'
),
vitals_raw AS (
  -- Pull relevant vitals from first 24h of ICU stay and map to canonical vital types
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    ce.itemid,
    di.label AS item_label,
    ce.charttime,
    ce.valuenum,
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%pulse%' THEN 'hr'
      WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%rr %' THEN 'rr'
      WHEN LOWER(di.label) LIKE '%systolic%' THEN 'sbp'
      WHEN LOWER(di.label) LIKE '%diastolic%' THEN 'dbp'
      WHEN LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%o2 sat%' THEN 'spo2'
      WHEN LOWER(di.label) LIKE '%temperature%' OR LOWER(di.label) LIKE 'temp %' THEN 'temp'
      ELSE NULL
    END AS vital
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort_stays s
    ON ce.subject_id = s.subject_id
    AND ce.hadm_id = s.hadm_id
    AND ce.stay_id = s.stay_id
  WHERE ce.valuenum IS NOT NULL
    -- Within first 24 hours of ICU stay
    AND ce.charttime >= s.intime
    AND ce.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    -- only keep mapped vitals
    AND (
      LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%pulse%'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%resp rate%'
      OR LOWER(di.label) LIKE '%systolic%'
      OR LOWER(di.label) LIKE '%diastolic%'
      OR LOWER(di.label) LIKE '%oxygen saturation%'
      OR LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%temperature%'
      OR LOWER(di.label) LIKE 'temp %'
    )
),
per_stay_worst AS (
  -- Compute per-stay "worst" value for each vital during first 24h
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    MAX(CASE WHEN vital = 'hr' THEN valuenum END) AS hr_max,
    MAX(CASE WHEN vital = 'rr' THEN valuenum END) AS rr_max,
    MIN(CASE WHEN vital = 'sbp' THEN valuenum END) AS sbp_min,
    MIN(CASE WHEN vital = 'dbp' THEN valuenum END) AS dbp_min,
    MIN(CASE WHEN vital = 'spo2' THEN valuenum END) AS spo2_min,
    -- Temperature instability measured as max absolute deviation from 37.0°C
    MAX(CASE WHEN vital = 'temp' THEN ABS(valuenum - 37.0) END) AS temp_dev_max
  FROM vitals_raw
  GROUP BY stay_id, subject_id, hadm_id
),
vital_stats AS (
  -- Cohort mean and sd of the per-stay worst values (used to compute z-scores)
  SELECT
    AVG(hr_max) AS hr_mean, STDDEV_SAMP(hr_max) AS hr_sd,
    AVG(rr_max) AS rr_mean, STDDEV_SAMP(rr_max) AS rr_sd,
    AVG(sbp_min) AS sbp_mean, STDDEV_SAMP(sbp_min) AS sbp_sd,
    AVG(dbp_min) AS dbp_mean, STDDEV_SAMP(dbp_min) AS dbp_sd,
    AVG(spo2_min) AS spo2_mean, STDDEV_SAMP(spo2_min) AS spo2_sd,
    AVG(temp_dev_max) AS temp_dev_mean, STDDEV_SAMP(temp_dev_max) AS temp_dev_sd
  FROM per_stay_worst
),
per_stay_scores AS (
  -- Compute z-scores per vital per stay and then aggregate to a single instability score.
  SELECT
    p.*,
    -- z-scores; orient so that larger positive means more abnormal for all vitals
    CASE WHEN v.hr_sd IS NULL OR v.hr_sd = 0 THEN NULL ELSE (p.hr_max - v.hr_mean) / v.hr_sd END AS hr_z,
    CASE WHEN v.rr_sd IS NULL OR v.rr_sd = 0 THEN NULL ELSE (p.rr_max - v.rr_mean) / v.rr_sd END AS rr_z,
    CASE WHEN v.sbp_sd IS NULL OR v.sbp_sd = 0 THEN NULL ELSE (v.sbp_mean - p.sbp_min) / v.sbp_sd END AS sbp_z,
    CASE WHEN v.dbp_sd IS NULL OR v.dbp_sd = 0 THEN NULL ELSE (v.dbp_mean - p.dbp_min) / v.dbp_sd END AS dbp_z,
    CASE WHEN v.spo2_sd IS NULL OR v.spo2_sd = 0 THEN NULL ELSE (v.spo2_mean - p.spo2_min) / v.spo2_sd END AS spo2_z,
    CASE WHEN v.temp_dev_sd IS NULL OR v.temp_dev_sd = 0 THEN NULL ELSE (p.temp_dev_max - v.temp_dev_mean) / v.temp_dev_sd END AS temp_z,
    -- instability score: 100 * sum of absolute z-scores across available vitals
    ROUND(
      100 *
      (
        COALESCE(ABS((CASE WHEN v.hr_sd IS NULL OR v.hr_sd = 0 THEN NULL ELSE (p.hr_max - v.hr_mean) / v.hr_sd END)), 0)
      + COALESCE(ABS((CASE WHEN v.rr_sd IS NULL OR v.rr_sd = 0 THEN NULL ELSE (p.rr_max - v.rr_mean) / v.rr_sd END)), 0)
      + COALESCE(ABS((CASE WHEN v.sbp_sd IS NULL OR v.sbp_sd = 0 THEN NULL ELSE (v.sbp_mean - p.sbp_min) / v.sbp_sd END)), 0)
      + COALESCE(ABS((CASE WHEN v.dbp_sd IS NULL OR v.dbp_sd = 0 THEN NULL ELSE (v.dbp_mean - p.dbp_min) / v.dbp_sd END)), 0)
      + COALESCE(ABS((CASE WHEN v.spo2_sd IS NULL OR v.spo2_sd = 0 THEN NULL ELSE (v.spo2_mean - p.spo2_min) / v.spo2_sd END)), 0)
      + COALESCE(ABS((CASE WHEN v.temp_dev_sd IS NULL OR v.temp_dev_sd = 0 THEN NULL ELSE (p.temp_dev_max - v.temp_dev_mean) / v.temp_dev_sd END)), 0)
      )
    , 2) AS instability_score
  FROM per_stay_worst p
  CROSS JOIN vital_stats v
),
scored_cohort AS (
  -- Keep only stays with at least one vital contributing (score > 0)
  SELECT
    s.*,
    icustays.los,
    admissions.hospital_expire_flag
  FROM per_stay_scores s
  JOIN cohort_stays cs ON s.stay_id = cs.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icustays
    ON s.stay_id = icustays.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON s.hadm_id = admissions.hadm_id
  WHERE s.instability_score IS NOT NULL
    AND s.instability_score > 0
),
ranked AS (
  -- Assign decile (NTILE 10) where NTILE=1 is the most unstable (highest score)
  SELECT
    sc.*,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_rank_desc
  FROM scored_cohort sc
),
summary AS (
  -- overall counts and percentile calculation for score = 70
  SELECT
    COUNT(*) AS n_stays,
    SUM(CASE WHEN instability_score <= 70 THEN 1 ELSE 0 END) AS n_le_70,
    ROUND(100.0 * SUM(CASE WHEN instability_score <= 70 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percentile_of_70
  FROM ranked
),
top_decile_stats AS (
  -- mean ICU LOS and mortality for the top (most unstable) decile (NTILE = 1)
  SELECT
    COUNT(*) AS n_top_decile,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS hospital_mortality_percent
  FROM ranked
  WHERE decile_rank_desc = 1
)

SELECT
  -- Percentile output for a score of 70
  s.n_stays AS cohort_size,
  s.n_le_70 AS stays_with_score_le_70,
  s.percentile_of_70 AS percentile_of_score_70,
  -- Top decile summary
  td.n_top_decile AS top_decile_size,
  td.mean_icu_los_days,
  td.hospital_mortality_percent
FROM summary s
CROSS JOIN top_decile_stats td;