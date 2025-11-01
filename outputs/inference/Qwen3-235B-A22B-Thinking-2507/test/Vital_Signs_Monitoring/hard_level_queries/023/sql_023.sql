WITH icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    -- Calculate age at ICU admission using MIMIC-IV anchor methodology
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 55 AND 65
),

hfnc_flag AS (
  SELECT 
    i.stay_id,
    MAX(CASE WHEN c.itemid = 228096 THEN 1 ELSE 0 END) AS has_hfnc
  FROM icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND c.itemid = 228096
  GROUP BY i.stay_id
),

vitals AS (
  SELECT 
    c.stay_id,
    -- Heart rate measurements (itemid 220045 = Heart Rate)
    SUM(CASE WHEN c.itemid = 220045 AND c.valuenum > 100 THEN 1 ELSE 0 END) AS hr_tachy_count,
    COUNT(CASE WHEN c.itemid = 220045 THEN 1 END) AS hr_total,
    -- Systolic BP measurements (itemid 220050 = Non Invasive Blood Pressure systolic)
    SUM(CASE WHEN c.itemid = 220050 AND c.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_hypo_count,
    COUNT(CASE WHEN c.itemid = 220050 THEN 1 END) AS sbp_total
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN icu_stays i
    ON c.stay_id = i.stay_id
    AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  WHERE c.itemid IN (220045, 220050)
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

mortality AS (
  SELECT 
    i.stay_id,
    a.hospital_expire_flag
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
),

cohort AS (
  SELECT
    i.stay_id,
    i.los AS icu_los,
    COALESCE(v.hr_tachy_count, 0) + COALESCE(v.sbp_hypo_count, 0) AS instability_score,
    CASE WHEN COALESCE(v.hr_total, 0) > 0 THEN COALESCE(v.hr_tachy_count, 0) * 1.0 / v.hr_total ELSE NULL END AS tachycardia_burden,
    CASE WHEN COALESCE(v.sbp_total, 0) > 0 THEN COALESCE(v.sbp_hypo_count, 0) * 1.0 / v.sbp_total ELSE NULL END AS hypotension_burden,
    m.hospital_expire_flag,
    hf.has_hfnc
  FROM icu_stays i
  LEFT JOIN hfnc_flag hf ON i.stay_id = hf.stay_id
  LEFT JOIN vitals v ON i.stay_id = v.stay_id
  LEFT JOIN mortality m ON i.stay_id = m.stay_id
)

SELECT
  has_hfnc,
  -- Instability score statistics
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(500)] AS instability_median,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(250)] AS instability_p25,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(750)] AS instability_p75,
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(950)] AS instability_p95,
  -- Tachycardia burden statistics
  APPROX_QUANTILES(tachycardia_burden, 1000)[OFFSET(500)] AS tachy_median,
  APPROX_QUANTILES(tachycardia_burden, 1000)[OFFSET(250)] AS tachy_p25,
  APPROX_QUANTILES(tachycardia_burden, 1000)[OFFSET(750)] AS tachy_p75,
  APPROX_QUANTILES(tachycardia_burden, 1000)[OFFSET(950)] AS tachy_p95,
  -- Hypotension burden statistics
  APPROX_QUANTILES(hypotension_burden, 1000)[OFFSET(500)] AS hypo_median,
  APPROX_QUANTILES(hypotension_burden, 1000)[OFFSET(250)] AS hypo_p25,
  APPROX_QUANTILES(hypotension_burden, 1000)[OFFSET(750)] AS hypo_p75,
  APPROX_QUANTILES(hypotension_burden, 1000)[OFFSET(950)] AS hypo_p95,
  -- ICU LOS statistics
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(500)] AS los_median,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(250)] AS los_p25,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(750)] AS los_p75,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(950)] AS los_p95,
  -- Mortality rate
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort
WHERE has_hfnc IS NOT NULL
GROUP BY has_hfnc;