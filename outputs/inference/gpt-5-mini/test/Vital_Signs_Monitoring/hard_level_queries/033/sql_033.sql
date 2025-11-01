WITH
-- 1) Base ICU stays for females aged 51-61
icustay_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (hadm_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- 2) Identify stays with evidence of invasive mechanical ventilation in first 48 hours
vent_rows AS (
  SELECT DISTINCT
    c.stay_id
  FROM
    icustay_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = c.stay_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%ventil%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%intubat%'
      OR LOWER(COALESCE(pe.ordercategoryname, '')) LIKE '%ventil%'
      OR LOWER(COALESCE(pe.ordercategoryname, '')) LIKE '%intubat%'
    )
),

-- 3) Restrict cohort to those with ventilation evidence
vent_cohort AS (
  SELECT
    c.*
  FROM
    icustay_cohort c
  JOIN
    vent_rows v USING (stay_id)
),

-- 4) Pull vital sign measurements in first 48 hours and classify vital type
vitals_raw AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    v.charttime,
    v.valuenum,
    LOWER(COALESCE(di.label, '')) AS item_label,
    CASE
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%heart rate%' THEN 'hr'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%respiratory rate%' THEN 'rr'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%resp rate%' THEN 'rr'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%resp rate%' THEN 'rr'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%resp%' AND (LOWER(COALESCE(di.label, '')) LIKE '%rate%') THEN 'rr'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%oxygen saturation%' THEN 'spo2'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%o2 sat%' THEN 'spo2'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%spo2%' THEN 'spo2'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%mean arterial%' THEN 'map'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%arterial bp mean%' THEN 'map'
      WHEN LOWER(COALESCE(di.label, '')) LIKE '%map%' THEN 'map'
      ELSE NULL
    END AS vital_type
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` v
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON v.itemid = di.itemid
  JOIN
    vent_cohort vc
    ON v.stay_id = vc.stay_id
  WHERE
    v.charttime BETWEEN vc.intime AND TIMESTAMP_ADD(vc.intime, INTERVAL 48 HOUR)
    AND v.valuenum IS NOT NULL
),

-- 5) Compute per-measurement abnormal flags per the chosen rules
vitals_abnormal AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    charttime,
    vital_type,
    valuenum,
    CASE
      WHEN vital_type = 'hr' AND valuenum > 120 THEN 1
      WHEN vital_type = 'map' AND valuenum < 65 THEN 1
      WHEN vital_type = 'spo2' AND valuenum < 90 THEN 1
      WHEN vital_type = 'rr' AND (valuenum < 8 OR valuenum > 30) THEN 1
      ELSE 0
    END AS abnormal_flag
  FROM
    vitals_raw
  WHERE
    vital_type IS NOT NULL
),

-- 6) Aggregate to a raw instability score per stay (sum of abnormal events)
instability_raw AS (
  SELECT
    vc.subject_id,
    vc.hadm_id,
    vc.stay_id,
    vc.intime,
    vc.outtime,
    vc.los,
    vc.hospital_expire_flag,
    COALESCE(SUM(abnormal_flag), 0) AS raw_score,
    COUNT(*) AS num_vital_measurements -- optional: how many vitals contributed
  FROM
    vent_cohort vc
  LEFT JOIN
    vitals_abnormal va
    USING (stay_id)
  GROUP BY
    vc.subject_id, vc.hadm_id, vc.stay_id, vc.intime, vc.outtime, vc.los, vc.hospital_expire_flag
),

-- 7) Scale raw scores to 0..100 by dividing by maximum raw score in the cohort
instability_scaled AS (
  SELECT
    ir.*,
    CASE WHEN max_raw = 0 THEN 0
         ELSE ROUND(100.0 * raw_score / max_raw, 2)
    END AS instability_score
  FROM
    instability_raw ir
  CROSS JOIN (
    SELECT GREATEST(MAX(raw_score), 0) AS max_raw
    FROM instability_raw
  )
),

-- 8) Compute percentile for a value of 80 (fraction of cohort with instability_score <= 80)
percentile_80 AS (
  SELECT
    COUNTIF(instability_score <= 80) AS n_at_or_below_80,
    COUNT(*) AS n_total,
    100.0 * COUNTIF(instability_score <= 80) / COUNT(*) AS pctile_of_80
  FROM
    instability_scaled
),

-- 9) Determine 90th-percentile cutoff (top decile) using approximate quantiles
decile_cutoff AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS cutoff_90
  FROM
    instability_scaled
),

-- 10) Stats for the most unstable decile (instability_score >= cutoff)
top_decile_stats AS (
  SELECT
    ds.cutoff_90,
    COUNT(*) AS n_top_decile,
    -- median LOS (approximate)
    (APPROX_QUANTILES(los, 100))[OFFSET(50)] AS median_los_days,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_pct
  FROM
    instability_scaled s
  CROSS JOIN
    decile_cutoff ds
  WHERE
    s.instability_score >= ds.cutoff_90
  GROUP BY
    ds.cutoff_90
)

-- Final output: percentile for score=80 and top-decile statistics
SELECT
  p.n_total AS cohort_size,
  p.n_at_or_below_80 AS n_stays_at_or_below_score_80,
  ROUND(p.pctile_of_80, 2) AS percentile_of_score_80,
  t.cutoff_90 AS instability_score_90th_percentile_cutoff,
  t.n_top_decile,
  t.median_los_days,
  t.hospital_mortality_pct
FROM
  percentile_80 p
CROSS JOIN
  top_decile_stats t;