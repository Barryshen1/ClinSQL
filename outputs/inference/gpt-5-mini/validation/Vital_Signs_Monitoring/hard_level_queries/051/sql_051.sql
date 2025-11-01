WITH
-- 1) Identify relevant vital itemids from ICU d_items by label pattern
vital_itemids AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%heart rate%'           -- heart rate
    OR LOWER(label) LIKE '%respiratory rate%'  -- resp rate
    OR LOWER(label) LIKE '%respiratory%'       -- broader respiratory labels
    OR LOWER(label) LIKE '%systolic%'          -- systolic BP (invasive/noninvasive/arterial)
    OR LOWER(label) LIKE '%diastolic%'         -- diastolic BP
    OR LOWER(label) LIKE '%spo2%'              -- SpO2 / oxygen saturation abbreviations
    OR LOWER(label) LIKE '%oxygen saturation%' -- oxygen saturation
    OR LOWER(label) LIKE '%temperature%'       -- temp
),

-- 2) Base cohort: male patients aged 89-99 and their icu stays
male_elderly_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),

-- 3) All relevant chart events in the first 48 hours for the cohort and selected vitals
vitals_48h AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    di.label AS item_label,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_itemids di
    ON ce.itemid = di.itemid
  JOIN male_elderly_icustays icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

-- 4) Flag each measurement as abnormal according to simple clinical thresholds (customize if needed)
vitals_flagged AS (
  SELECT
    v.*,
    CASE
      WHEN LOWER(item_label) LIKE '%heart rate%' AND (valuenum < 40 OR valuenum > 140) THEN 1
      WHEN LOWER(item_label) LIKE '%respiratory rate%' AND (valuenum < 8 OR valuenum > 30) THEN 1
      WHEN (LOWER(item_label) LIKE '%systolic%') AND (valuenum < 90 OR valuenum > 200) THEN 1
      WHEN (LOWER(item_label) LIKE '%diastolic%') AND (valuenum < 40 OR valuenum > 120) THEN 1
      WHEN (LOWER(item_label) LIKE '%spo2%' OR LOWER(item_label) LIKE '%oxygen saturation%') AND (valuenum < 90) THEN 1
      WHEN LOWER(item_label) LIKE '%temperature%' AND (valuenum < 35 OR valuenum > 39) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM vitals_48h v
),

-- 5) For abnormal measurements, determine episode starts per (stay_id, itemid) when gap > 60 minutes
abnormal_with_episodes AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    itemid,
    item_label,
    charttime,
    valuenum,
    is_abnormal,
    LAG(charttime) OVER (PARTITION BY stay_id, itemid ORDER BY charttime) AS prev_charttime
  FROM vitals_flagged
  WHERE is_abnormal = 1
),

-- Mark episode starts: first abnormal for (stay,item) or gap > 60 minutes since prior abnormal
episode_starts AS (
  SELECT
    *,
    CASE
      WHEN prev_charttime IS NULL THEN 1
      WHEN TIMESTAMP_DIFF(charttime, prev_charttime, MINUTE) > 60 THEN 1
      ELSE 0
    END AS episode_start
  FROM abnormal_with_episodes
),

-- 6) Aggregate per ICU stay: instability_score = count abnormal measurements; abnormal_episodes = count episode starts
stay_instability AS (
  -- abnormal counts & episodes from measurements
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    COALESCE(sum_abn.abn_count, 0) AS instability_score,
    COALESCE(sum_flag.episode_count, 0) AS abnormal_episodes
  FROM male_elderly_icustays icu
  LEFT JOIN (
    SELECT
      stay_id,
      COUNT(1) AS abn_count
    FROM vitals_flagged
    WHERE is_abnormal = 1
    GROUP BY stay_id
  ) AS sum_abn
    ON icu.stay_id = sum_abn.stay_id
  LEFT JOIN (
    SELECT
      stay_id,
      SUM(episode_start) AS episode_count
    FROM episode_starts
    GROUP BY stay_id
  ) AS sum_flag
    ON icu.stay_id = sum_flag.stay_id
),

-- 7) Flag ischemic stroke admissions (per hadm_id) using diagnoses_icd (ICD-9/10 pattern matching)
stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    -- ICD-9
    (d.icd_version = 9 AND (d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code = '436'))
    OR
    -- ICD-10
    (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
),

-- 8) Combine stays with instability metrics, stroke flag, LOS and mortality
stays_with_metrics AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    si.instability_score,
    si.abnormal_episodes,
    s.los,
    s.hospital_expire_flag,
    CASE WHEN st.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ischemic_stroke_flag
  FROM male_elderly_icustays s
  LEFT JOIN stay_instability si
    ON s.stay_id = si.stay_id
  LEFT JOIN stroke_admissions st
    ON s.hadm_id = st.hadm_id
),

-- 9) Calculate percentiles:
--  - 95th percentile of instability among ischemic stroke stays
--  - 75th percentile (top quartile threshold) of instability among all male 89-99 ICU stays
percentiles AS (
  SELECT
    (SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)]
     FROM stays_with_metrics
     WHERE ischemic_stroke_flag = 1) AS stroke_95th_instability,
    (SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)]
     FROM stays_with_metrics) AS cohort_75th_instability
)

-- Final: report requested results
SELECT
  p.stroke_95th_instability AS ischemic_stroke_95th_pct_instability_48h,
  comp.group_label,
  comp.n_stays,
  comp.mean_instability_score,
  comp.mean_abnormal_episodes,
  comp.mean_icu_los_hrs,
  comp.mortality_fraction
FROM percentiles p
CROSS JOIN (
  -- For top quartile (instability_score >= cohort_75th_instability) produce two rows:
  -- A) ischemic stroke subset
  -- B) all stays (general ICU) in top quartile
  SELECT
    'Ischemic stroke' AS group_label,
    COUNT(*) AS n_stays,
    ROUND(AVG(instability_score), 3) AS mean_instability_score,
    ROUND(AVG(abnormal_episodes), 3) AS mean_abnormal_episodes,
    ROUND(AVG(los * 24), 3) AS mean_icu_los_hrs,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS mortality_fraction
  FROM stays_with_metrics
  WHERE instability_score >= (SELECT cohort_75th_instability FROM percentiles)
    AND ischemic_stroke_flag = 1

  UNION ALL

  SELECT
    'All (general ICU)' AS group_label,
    COUNT(*) AS n_stays,
    ROUND(AVG(instability_score), 3) AS mean_instability_score,
    ROUND(AVG(abnormal_episodes), 3) AS mean_abnormal_episodes,
    ROUND(AVG(los * 24), 3) AS mean_icu_los_hrs,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS mortality_fraction
  FROM stays_with_metrics
  WHERE instability_score >= (SELECT cohort_75th_instability FROM percentiles)
) AS comp
ORDER BY comp.group_label;