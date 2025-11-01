WITH cohort AS (
  -- ICU stays for female patients age 49-59 with an ACS diagnosis on the admission
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%acute myocardial%'
          OR LOWER(dd.long_title) LIKE '%acute coronary%'
          OR LOWER(dd.long_title) LIKE '%unstable angina%'
        )
    )
),

-- Aggregate worst/best vital values in the FIRST 24 HOURS of ICU stay
vitals_first24 AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    -- worst (most abnormal) summaries in first 24h
    MAX(CASE WHEN LOWER(d.label) LIKE '%heart rate%' THEN ce.valuenum END) AS hr_max,
    MAX(CASE WHEN LOWER(d.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr_max,
    MIN(CASE WHEN (LOWER(d.label) LIKE '%spo2%' OR LOWER(d.label) LIKE '%oxygen saturation%') THEN ce.valuenum END) AS spo2_min,
    MIN(CASE WHEN LOWER(d.label) LIKE '%systolic%' THEN ce.valuenum END) AS sbp_min,
    MAX(CASE WHEN LOWER(d.label) LIKE '%temperature%' OR LOWER(d.label) LIKE '%temp%' THEN ce.valuenum END) AS temp_max
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    -- limit to likely vital sign item labels using patterns (robust to label variants)
    AND (
      LOWER(d.label) LIKE '%heart rate%'
      OR LOWER(d.label) LIKE '%respiratory rate%'
      OR LOWER(d.label) LIKE '%spo2%'
      OR LOWER(d.label) LIKE '%oxygen saturation%'
      OR LOWER(d.label) LIKE '%systolic%'
      OR LOWER(d.label) LIKE '%temperature%'
      OR LOWER(d.label) LIKE '%temp%'
    )
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),

-- Compute cohort-level means and standard deviations for standardization
vital_stats AS (
  SELECT
    AVG(hr_max) AS hr_mean, STDDEV_POP(hr_max) AS hr_sd,
    AVG(rr_max) AS rr_mean, STDDEV_POP(rr_max) AS rr_sd,
    AVG(spo2_min) AS spo2_mean, STDDEV_POP(spo2_min) AS spo2_sd,
    AVG(sbp_min) AS sbp_mean, STDDEV_POP(sbp_min) AS sbp_sd,
    AVG(temp_max) AS temp_mean, STDDEV_POP(temp_max) AS temp_sd
  FROM vitals_first24
),

-- Compute z-scores (direction: higher z = worse) and composite_raw
scores_raw AS (
  SELECT
    v.*,
    -- z-scores; NULL sd protected by NULLIF
    SAFE_DIVIDE(v.hr_max - s.hr_mean, NULLIF(s.hr_sd, 0))   AS z_hr,
    SAFE_DIVIDE(v.rr_max - s.rr_mean, NULLIF(s.rr_sd, 0))   AS z_rr,
    -- for spo2 and sbp lower = worse, so invert direction (mean - value)
    SAFE_DIVIDE(s.spo2_mean - v.spo2_min, NULLIF(s.spo2_sd, 0)) AS z_spo2,
    SAFE_DIVIDE(s.sbp_mean - v.sbp_min, NULLIF(s.sbp_sd, 0))     AS z_sbp,
    SAFE_DIVIDE(v.temp_max - s.temp_mean, NULLIF(s.temp_sd, 0)) AS z_temp,
    -- sum z-scores; treat NULLs as 0 (no contribution)
    COALESCE(SAFE_DIVIDE(v.hr_max - s.hr_mean, NULLIF(s.hr_sd, 0)), 0)
    + COALESCE(SAFE_DIVIDE(v.rr_max - s.rr_mean, NULLIF(s.rr_sd, 0)), 0)
    + COALESCE(SAFE_DIVIDE(s.spo2_mean - v.spo2_min, NULLIF(s.spo2_sd, 0)), 0)
    + COALESCE(SAFE_DIVIDE(s.sbp_mean - v.sbp_min, NULLIF(s.sbp_sd, 0)), 0)
    + COALESCE(SAFE_DIVIDE(v.temp_max - s.temp_mean, NULLIF(s.temp_sd, 0)), 0)
    AS composite_raw
  FROM vitals_first24 v
  CROSS JOIN vital_stats s
),

-- Scale composite_raw to 0-100 across the cohort
scores_scaled AS (
  SELECT
    sr.*,
    -- compute cohort min/max then scale
    MIN(composite_raw) OVER() AS comp_min,
    MAX(composite_raw) OVER() AS comp_max,
    CASE
      WHEN MAX(composite_raw) OVER() = MIN(composite_raw) OVER() THEN 50.0
      ELSE 100.0 * SAFE_DIVIDE((composite_raw - MIN(composite_raw) OVER()), (MAX(composite_raw) OVER() - MIN(composite_raw) OVER()))
    END AS composite_score -- 0..100
  FROM scores_raw sr
),

-- 90th percentile threshold (approx) for top decile
decile_threshold AS (
  SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS threshold_90
  FROM scores_scaled
)

-- Final aggregation using scalar subqueries to avoid mixing aggregates and non-aggregated columns
SELECT
  -- Percentile rank of a composite_score of 70: percent of cohort <= 70
  (SELECT ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN composite_score <= 70 THEN 1 ELSE 0 END), COUNT(1)), 2)
   FROM scores_scaled) AS percentile_of_70_pct,

  -- Top-decile count
  (SELECT COUNT(1)
   FROM scores_scaled s2
   WHERE s2.composite_score >= (SELECT threshold_90 FROM decile_threshold)
  ) AS top_decile_n,

  -- Mean ICU LOS (days) among top-decile stays
  (SELECT ROUND(AVG(icu.los), 3)
   FROM scores_scaled s3
   JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
     ON s3.stay_id = icu.stay_id
   WHERE s3.composite_score >= (SELECT threshold_90 FROM decile_threshold)
  ) AS top_decile_mean_icu_los_days,

  -- Hospital mortality (%) among top-decile (use admissions.hospital_expire_flag)
  (SELECT ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END),
                                    NULLIF(COUNT(1), 0)), 2)
   FROM scores_scaled s4
   JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
     ON s4.hadm_id = adm.hadm_id
   WHERE s4.composite_score >= (SELECT threshold_90 FROM decile_threshold)
  ) AS top_decile_hospital_mortality_pct,

  -- Threshold score used for top decile (0-100 scale)
  ROUND((SELECT threshold_90 FROM decile_threshold), 2) AS top_decile_threshold_score;