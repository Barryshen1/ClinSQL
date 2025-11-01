WITH cohort AS (
  -- Base cohort: first ICU stay for males aged 55-65
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    i.first_careunit,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND i.los > 0
    AND i.first_careunit IN ('MICU', 'SICU')  -- Focus on relevant ICUs
  QUALIFY rn = 1
),

hfnc_cohort AS (
  -- Flag HFNC usage within 24h of intime
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
        WHERE ie.stay_id = c.stay_id
          AND ie.itemid IN (225470, 227910)  -- HFNC itemids (confirm via d_items)
          AND ie.amount > 0
          AND ie.starttime >= c.intime
          AND ie.starttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
      ) THEN 1 ELSE 0 
    END AS hfnc_used
  FROM cohort c
),

resp_dx AS (
  -- Pre-compute respiratory diagnosis flag
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_respiratory_dx
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.icd_code LIKE 'J96%'  -- Acute respiratory failure
    AND dd.long_title LIKE '%respiratory failure%'
),

matched_controls AS (
  -- Condition-matched: HFNC users + controls with respiratory dx (hfnc_used=0)
  SELECT 
    hc.*,
    COALESCE(rdx.has_respiratory_dx, 0) AS has_respiratory_dx
  FROM hfnc_cohort hc
  LEFT JOIN resp_dx rdx
    ON hc.subject_id = rdx.subject_id AND hc.hadm_id = rdx.hadm_id
  WHERE hc.hfnc_used = 1 
     OR (hc.hfnc_used = 0 AND rdx.has_respiratory_dx = 1)
),

hr_times AS (
  -- Subquery for HR time differences (tachycardia burden)
  SELECT 
    stay_id,
    charttime,
    valuenum,
    intime,
    LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_time,
    UNIX_SECONDS(charttime - LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime)) AS time_diff_sec,
    UNIX_SECONDS(DATETIME_ADD(intime, INTERVAL 24 HOUR) - intime) AS total_sec
  FROM matched_controls mc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON mc.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- HR
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= mc.intime
    AND ce.charttime <= DATETIME_ADD(mc.intime, INTERVAL 24 HOUR)
),

map_times AS (
  -- Subquery for MAP time differences (hypotension burden)
  SELECT 
    stay_id,
    charttime,
    valuenum,
    intime,
    LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_time,
    UNIX_SECONDS(charttime - LAG(charttime) OVER (PARTITION BY stay_id ORDER BY charttime)) AS time_diff_sec,
    UNIX_SECONDS(DATETIME_ADD(intime, INTERVAL 24 HOUR) - intime) AS total_sec
  FROM matched_controls mc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON mc.stay_id = ce.stay_id
  WHERE ce.itemid = 220052  -- MAP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= mc.intime
    AND ce.charttime <= DATETIME_ADD(mc.intime, INTERVAL 24 HOUR)
),

vitals_burdens AS (
  -- Compute burdens using time diffs; assume gaps filled by interpolation (conservative: only sum abnormal diffs)
  SELECT 
    mc.stay_id,
    mc.hfnc_used,
    mc.los,
    mc.hospital_expire_flag,
    -- Tachycardia: sum time_diff where HR > 100, divide by total 24h sec
    SAFE_DIVIDE(
      (SELECT SUM(CASE WHEN ht.valuenum > 100 AND ht.time_diff_sec > 0 THEN ht.time_diff_sec ELSE 0 END)
       FROM hr_times ht WHERE ht.stay_id = mc.stay_id),
      24 * 3600.0
    ) * 100 AS tachy_burden_pct,
    -- Hypotension: sum time_diff where MAP < 65
    SAFE_DIVIDE(
      (SELECT SUM(CASE WHEN mt.valuenum < 65 AND mt.time_diff_sec > 0 THEN mt.time_diff_sec ELSE 0 END)
       FROM map_times mt WHERE mt.stay_id = mc.stay_id),
      24 * 3600.0
    ) * 100 AS hypo_burden_pct,
    -- Instability score: avg normalized burdens (0-1)
    SAFE_DIVIDE(
      (SAFE_DIVIDE(COALESCE((SELECT SUM(CASE WHEN ht.valuenum > 100 AND ht.time_diff_sec > 0 THEN ht.time_diff_sec ELSE 0 END)
                            FROM hr_times ht WHERE ht.stay_id = mc.stay_id), 0), 24 * 3600.0) +
       SAFE_DIVIDE(COALESCE((SELECT SUM(CASE WHEN mt.valuenum < 65 AND mt.time_diff_sec > 0 THEN mt.time_diff_sec ELSE 0 END)
                            FROM map_times mt WHERE mt.stay_id = mc.stay_id), 0), 24 * 3600.0)) / 2,
      1.0
    ) AS instability_score
  FROM matched_controls mc
),

aggregated_metrics AS (
  SELECT 
    vb.hfnc_used,
    -- Instability score percentiles
    PERCENTILE_CONT(vb.instability_score, 0.5) OVER (PARTITION BY vb.hfnc_used) AS median_instability,
    PERCENTILE_CONT(vb.instability_score, 0.25) OVER (PARTITION BY vb.hfnc_used) AS p25_instability,
    PERCENTILE_CONT(vb.instability_score, 0.75) OVER (PARTITION BY vb.hfnc_used) AS p75_instability,
    PERCENTILE_CONT(vb.instability_score, 0.95) OVER (PARTITION BY vb.hfnc_used) AS p95_instability,
    -- Burden medians
    PERCENTILE_CONT(vb.tachy_burden_pct, 0.5) OVER (PARTITION BY vb.hfnc_used) AS median_tachy_burden,
    PERCENTILE_CONT(vb.hypo_burden_pct, 0.5) OVER (PARTITION BY vb.hfnc_used) AS median_hypo_burden,
    -- LOS and mortality
    PERCENTILE_CONT(vb.los, 0.5) OVER (PARTITION BY vb.hfnc_used) AS median_icu_los,
    AVG(CAST(vb.hospital_expire_flag AS FLOAT)) * 100 OVER (PARTITION BY vb.hfnc_used) AS mortality_rate_pct,
    COUNT(*) OVER (PARTITION BY vb.hfnc_used) AS n_patients
  FROM vitals_burdens vb
  GROUP BY vb.hfnc_used
)

SELECT 
  CASE WHEN hfnc_used = 1 THEN 'HFNC' ELSE 'Controls' END AS group_name,
  median_instability,
  p25_instability,
  p75_instability,
  p95_instability,
  median_tachy_burden,
  median_hypo_burden,
  median_icu_los,
  mortality_rate_pct,
  n_patients
FROM aggregated_metrics
ORDER BY hfnc_used;