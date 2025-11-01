WITH
-- 1) Identify itemids for the vitals of interest using ICU d_items labels (case-insensitive LIKE)
vital_itemids AS (
  SELECT itemid,
         LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),
hr_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%heart rate%' OR label LIKE '%hr %' OR label LIKE '%heartrate%' LIMIT 1000
),
rr_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%respiratory rate%' OR label LIKE '%resp rate%' OR label LIKE '%respiration rate%' LIMIT 1000
),
sysbp_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%systolic%' AND (label LIKE '%blood pressure%' OR label LIKE '%bp%') LIMIT 1000
),
spo2_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%spo2%' OR label LIKE '%oxygen saturation%' OR label LIKE '%o2 saturation%' LIMIT 1000
),
temp_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%temperature%' OR label LIKE '%temp%' LIMIT 1000
),
gcs_items AS (
  SELECT itemid FROM vital_itemids WHERE label LIKE '%glasgow%' OR label LIKE '%gcs%' LIMIT 1000
),

-- 2) Cohort: male patients age 78-88 with sepsis diagnosis and an ICU stay
sepsis_cohort AS (
  SELECT DISTINCT icu.subject_id,
         icu.hadm_id,
         icu.stay_id,
         icu.intime,
         icu.outtime,
         icu.los,
         p.anchor_age,
         p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id AND icu.subject_id = a.subject_id
  -- require sepsis diagnosis on the admission
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id AND icu.subject_id = dx.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(ddx.long_title) LIKE '%sepsis%'
),

-- 3) Extract vitals in first 24 hours and map to vitals of interest
vital_observations AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sepsis_cohort sc
    ON ce.stay_id = sc.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN sc.intime AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
),

-- 4) For each stay, compute whether any abnormal measurement occurred per vital in the first 24 hours
vital_flags AS (
  SELECT
    sc.stay_id,
    -- Heart rate abnormal flag
    MAX(CASE
          WHEN vi_hr.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 50 OR vo.valuenum > 120)
          THEN 1 ELSE 0 END) AS hr_abn,
    -- Respiratory rate abnormal flag
    MAX(CASE
          WHEN vi_rr.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 8 OR vo.valuenum > 30)
          THEN 1 ELSE 0 END) AS rr_abn,
    -- Systolic BP abnormal flag
    MAX(CASE
          WHEN vi_sys.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 90 OR vo.valuenum > 180)
          THEN 1 ELSE 0 END) AS sysbp_abn,
    -- SpO2 abnormal flag
    MAX(CASE
          WHEN vi_spo2.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 90)
          THEN 1 ELSE 0 END) AS spo2_abn,
    -- Temperature abnormal flag
    MAX(CASE
          WHEN vi_temp.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 36 OR vo.valuenum > 38.5)
          THEN 1 ELSE 0 END) AS temp_abn,
    -- GCS abnormal flag
    MAX(CASE
          WHEN vi_gcs.itemid IS NOT NULL AND vo.valuenum IS NOT NULL
               AND (vo.valuenum < 13)
          THEN 1 ELSE 0 END) AS gcs_abn
  FROM sepsis_cohort sc
  LEFT JOIN vital_observations vo
    ON vo.stay_id = sc.stay_id
  -- join itemid membership to identify which measurement each observation corresponds to
  LEFT JOIN hr_items vi_hr ON vo.itemid = vi_hr.itemid
  LEFT JOIN rr_items vi_rr ON vo.itemid = vi_rr.itemid
  LEFT JOIN sysbp_items vi_sys ON vo.itemid = vi_sys.itemid
  LEFT JOIN spo2_items vi_spo2 ON vo.itemid = vi_spo2.itemid
  LEFT JOIN temp_items vi_temp ON vo.itemid = vi_temp.itemid
  LEFT JOIN gcs_items vi_gcs ON vo.itemid = vi_gcs.itemid
  GROUP BY sc.stay_id
),

-- 5) Build instability percentage (0-100) per stay. Use 6 possible vitals.
instability_per_stay AS (
  SELECT
    sc.stay_id,
    sc.subject_id,
    sc.hadm_id,
    sc.intime,
    sc.outtime,
    sc.los,
    COALESCE(vf.hr_abn, 0) AS hr_abn,
    COALESCE(vf.rr_abn, 0) AS rr_abn,
    COALESCE(vf.sysbp_abn, 0) AS sysbp_abn,
    COALESCE(vf.spo2_abn, 0) AS spo2_abn,
    COALESCE(vf.temp_abn, 0) AS temp_abn,
    COALESCE(vf.gcs_abn, 0) AS gcs_abn,
    -- instability percent scaled to 0-100
    100.0 * (COALESCE(vf.hr_abn, 0)
           + COALESCE(vf.rr_abn, 0)
           + COALESCE(vf.sysbp_abn, 0)
           + COALESCE(vf.spo2_abn, 0)
           + COALESCE(vf.temp_abn, 0)
           + COALESCE(vf.gcs_abn, 0)
           ) / 6.0 AS instability_pct
  FROM sepsis_cohort sc
  LEFT JOIN vital_flags vf
    ON sc.stay_id = vf.stay_id
),

-- 6) Assign quartiles by instability_pct for the cohort
instability_with_quartile AS (
  SELECT
    ips.*,
    NTILE(4) OVER (ORDER BY instability_pct ASC) AS instability_quartile
  FROM instability_per_stay ips
),

-- 7) Compute metrics: percentile of 85 and quartile 4 summary
cohort_metrics AS (
  SELECT
    -- percentile rank of the score 85: percent of cohort with instability_pct <= 85
    100.0 * SUM(CASE WHEN instability_pct <= 85 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_85,
    -- Quartile 4 aggregates
    AVG(CASE WHEN instability_quartile = 4 THEN los END) AS quartile4_mean_icu_los,
    AVG(CASE WHEN instability_quartile = 4 THEN a.hospital_expire_flag END) AS quartile4_hospital_mortality
  FROM instability_with_quartile ips
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ips.hadm_id = a.hadm_id AND ips.subject_id = a.subject_id
)

SELECT
  ROUND(percentile_of_85, 2) AS percentile_of_score_85_pct,
  ROUND(quartile4_mean_icu_los, 3) AS quartile4_mean_icu_los_days,
  ROUND(quartile4_hospital_mortality, 4) AS quartile4_hospital_mortality_prop,
  ROUND(100.0 * quartile4_hospital_mortality, 2) AS quartile4_hospital_mortality_pct
FROM cohort_metrics;