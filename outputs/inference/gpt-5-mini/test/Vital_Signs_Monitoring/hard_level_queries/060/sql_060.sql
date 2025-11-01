WITH
-- Identify admissions with HHS diagnosis (by diagnosis description containing 'hyperosmolar')
hhs_adms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND COALESCE(di.icd_version, 9) = COALESCE(d.icd_version, di.icd_version)
  WHERE LOWER(d.long_title) LIKE '%hyperosmolar%'
),

-- Base cohort: male ICU stays, ages 78-88 inclusive
icu_cohort AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    CASE WHEN h.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_hhs
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING(subject_id, hadm_id)
  LEFT JOIN hhs_adms h
    ON s.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- Pull relevant numeric vitals in the first 48 hours and map to vital types
vitals_first48 AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    ce.charttime,
    ci.itemid,
    ci.label,
    ce.valuenum,
    -- map to vital types by d_items.label patterns
    CASE
      WHEN LOWER(ci.label) LIKE '%heart rate%' OR LOWER(ci.label) LIKE '%pulse%' THEN 'hr'
      WHEN LOWER(ci.label) LIKE '%systolic%' THEN 'sbp'
      WHEN LOWER(ci.label) LIKE '%respiratory rate%' OR LOWER(ci.label) LIKE '%resp rate%' OR LOWER(ci.label) LIKE '%rr%' THEN 'rr'
      WHEN LOWER(ci.label) LIKE '%oxygen saturation%' OR LOWER(ci.label) LIKE '%o2 sat%' OR LOWER(ci.label) LIKE '%spo2%' OR LOWER(ci.label) LIKE '%oximetry%' THEN 'spo2'
      WHEN LOWER(ci.label) LIKE '%temperature%' OR LOWER(ci.label) LIKE '%temp%' THEN 'temp'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` ci
    USING(itemid)
  JOIN icu_cohort s
    ON ce.subject_id = s.subject_id
    AND ce.hadm_id = s.hadm_id
    AND ce.stay_id = s.stay_id
  WHERE ce.charttime >= s.intime
    AND ce.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    -- only keep mapped vital types
    AND (
      LOWER(ci.label) LIKE '%heart rate%' OR LOWER(ci.label) LIKE '%pulse%'
      OR LOWER(ci.label) LIKE '%systolic%'
      OR LOWER(ci.label) LIKE '%respiratory rate%' OR LOWER(ci.label) LIKE '%resp rate%' OR LOWER(ci.label) LIKE '%rr%'
      OR LOWER(ci.label) LIKE '%oxygen saturation%' OR LOWER(ci.label) LIKE '%o2 sat%' OR LOWER(ci.label) LIKE '%spo2%' OR LOWER(ci.label) LIKE '%oximetry%'
      OR LOWER(ci.label) LIKE '%temperature%' OR LOWER(ci.label) LIKE '%temp%'
    )
),

-- Flag abnormal observations according to thresholds
vitals_flagged AS (
  SELECT
    v.*,
    -- Abnormal rules (adjustable)
    CASE
      WHEN vital_type = 'hr'  AND (valuenum < 50 OR valuenum > 120) THEN 1
      WHEN vital_type = 'sbp' AND (valuenum < 90) THEN 1
      WHEN vital_type = 'rr'  AND (valuenum < 8 OR valuenum > 30) THEN 1
      WHEN vital_type = 'spo2' AND (valuenum < 90) THEN 1
      WHEN vital_type = 'temp' AND (valuenum < 36 OR valuenum > 38) THEN 1
      ELSE 0
    END AS is_abnormal,
    -- hour offset from intime (0..47)
    TIMESTAMP_DIFF(v.charttime, v.intime, HOUR) AS hour_offset
  FROM vitals_first48 v
),

-- Per-stay, per-vital-type summary over first 48h to compute proportion abnormal
per_stay_vital_summary AS (
  SELECT
    stay_id,
    vital_type,
    COUNT(1) AS n_obs,
    SUM(is_abnormal) AS n_abnormal
  FROM vitals_flagged
  GROUP BY stay_id, vital_type
),

-- Pivot to compute one row per stay with composite instability score (sum of proportions)
per_stay_composite AS (
  -- start from the cohort so stays with missing vitals are included
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.intime,
    c.los,
    c.hospital_expire_flag,
    c.is_hhs,
    -- For each vital type, get n_abnormal and n_obs; if missing set to 0
    COALESCE((SELECT n_abnormal FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'hr'), 0) AS hr_n_abnormal,
    COALESCE((SELECT n_obs FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'hr'), 0) AS hr_n_obs,
    COALESCE((SELECT n_abnormal FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'sbp'), 0) AS sbp_n_abnormal,
    COALESCE((SELECT n_obs FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'sbp'), 0) AS sbp_n_obs,
    COALESCE((SELECT n_abnormal FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'rr'), 0) AS rr_n_abnormal,
    COALESCE((SELECT n_obs FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'rr'), 0) AS rr_n_obs,
    COALESCE((SELECT n_abnormal FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'spo2'), 0) AS spo2_n_abnormal,
    COALESCE((SELECT n_obs FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'spo2'), 0) AS spo2_n_obs,
    COALESCE((SELECT n_abnormal FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'temp'), 0) AS temp_n_abnormal,
    COALESCE((SELECT n_obs FROM per_stay_vital_summary v WHERE v.stay_id = c.stay_id AND v.vital_type = 'temp'), 0) AS temp_n_obs
  FROM icu_cohort c
),

-- Compute composite instability score per stay:
-- sum over vital types of (n_abnormal / n_obs) with proportion 0 when n_obs = 0
per_stay_metrics AS (
  SELECT
    p.stay_id,
    p.subject_id,
    p.hadm_id,
    p.is_hhs,
    p.los,
    p.hospital_expire_flag AS mortality_flag,
    -- proportions (guard against divide by zero)
    IF(p.hr_n_obs = 0, 0.0, SAFE_CAST(p.hr_n_abnormal AS FLOAT64) / p.hr_n_obs) AS hr_prop_abnormal,
    IF(p.sbp_n_obs = 0, 0.0, SAFE_CAST(p.sbp_n_abnormal AS FLOAT64) / p.sbp_n_obs) AS sbp_prop_abnormal,
    IF(p.rr_n_obs = 0, 0.0, SAFE_CAST(p.rr_n_abnormal AS FLOAT64) / p.rr_n_obs) AS rr_prop_abnormal,
    IF(p.spo2_n_obs = 0, 0.0, SAFE_CAST(p.spo2_n_abnormal AS FLOAT64) / p.spo2_n_obs) AS spo2_prop_abnormal,
    IF(p.temp_n_obs = 0, 0.0, SAFE_CAST(p.temp_n_abnormal AS FLOAT64) / p.temp_n_obs) AS temp_prop_abnormal
  FROM per_stay_composite p
),

-- compute composite score and total abnormal observation count (for alternate metrics)
per_stay_scores AS (
  SELECT
    s.*,
    -- composite instability score: sum of the five proportions (range 0..5)
    (hr_prop_abnormal + sbp_prop_abnormal + rr_prop_abnormal + spo2_prop_abnormal + temp_prop_abnormal) AS composite_instability_score
  FROM per_stay_metrics s
),

-- Compute mean abnormal-vital burden: average number of distinct abnormal vital types per hour across the first 48 hours.
-- For each stay and each hour (0..47), count distinct vital types that had any abnormal measurement in that hour, then average across all 48 hours.
hourly_abnormal_counts AS (
  SELECT
    s.stay_id,
    hour_offset,
    COALESCE(ab.cnt, 0) AS abnormal_vital_types_in_hour
  FROM (
    SELECT stay_id FROM icu_cohort
  ) s
  CROSS JOIN UNNEST(GENERATE_ARRAY(0,47)) AS hour_offset
  LEFT JOIN (
    -- count distinct vital types with abnormal in that hour for each stay
    SELECT
      vf.stay_id,
      vf.hour_offset,
      COUNT(DISTINCT vf.vital_type) AS cnt
    FROM vitals_flagged vf
    WHERE vf.is_abnormal = 1
      AND vf.hour_offset BETWEEN 0 AND 47
    GROUP BY vf.stay_id, vf.hour_offset
  ) ab
  ON s.stay_id = ab.stay_id AND hour_offset = ab.hour_offset
),

per_stay_abnormal_burden AS (
  SELECT
    stay_id,
    -- average across 48 hourly buckets (0..47)
    AVG(abnormal_vital_types_in_hour) AS mean_abnormal_vital_types_per_hour
  FROM hourly_abnormal_counts
  GROUP BY stay_id
),

-- Join per-stay composite score, mean abnormal burden, LOS and mortality into one table
per_stay_final AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.is_hhs,
    s.composite_instability_score,
    COALESCE(b.mean_abnormal_vital_types_per_hour, 0.0) AS mean_abnormal_burden,
    s.los,
    s.mortality_flag
  FROM per_stay_scores s
  LEFT JOIN per_stay_abnormal_burden b
    ON s.stay_id = b.stay_id
)

-- Final aggregation: for each group (HHS vs Control) compute n and 25th/50th/75th percentiles
SELECT
  CASE WHEN is_hhs = 1 THEN 'HHS' ELSE 'Control' END AS group_label,
  COUNT(1) AS n_stays,
  -- composite instability score quantiles (approx)
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(25)] AS composite_q25,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(50)] AS composite_median,
  APPROX_QUANTILES(composite_instability_score, 100)[OFFSET(75)] AS composite_q75,
  -- mean abnormal-vital burden quantiles (approx)
  APPROX_QUANTILES(mean_abnormal_burden, 100)[OFFSET(25)] AS abnburden_q25,
  APPROX_QUANTILES(mean_abnormal_burden, 100)[OFFSET(50)] AS abnburden_median,
  APPROX_QUANTILES(mean_abnormal_burden, 100)[OFFSET(75)] AS abnburden_q75,
  -- ICU LOS quantiles (approx)
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_q25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS los_median,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS los_q75,
  -- mortality (hospital_expire_flag) quantiles (approx; note this is binary so quantiles will reflect distribution)
  APPROX_QUANTILES(mortality_flag, 100)[OFFSET(25)] AS mort_q25,
  APPROX_QUANTILES(mortality_flag, 100)[OFFSET(50)] AS mort_median,
  APPROX_QUANTILES(mortality_flag, 100)[OFFSET(75)] AS mort_q75,
  -- also provide mean (rate) for LOS and mortality for clarity
  AVG(los) AS mean_los,
  AVG(mortality_flag) AS mortality_rate
FROM per_stay_final
GROUP BY is_hhs
ORDER BY is_hhs DESC;