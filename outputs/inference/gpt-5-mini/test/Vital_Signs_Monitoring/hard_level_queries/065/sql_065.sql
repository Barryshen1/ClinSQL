WITH
-- 1) cohort: male patients age 70-80 with their ICU stays
icu_cohort AS (
  SELECT icu.*, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- 2) map itemids for each vital type (based on d_items.label)
map_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%' OR LOWER(label) LIKE '% mean arterial %' OR LOWER(label) LIKE '%map%'
),
hr_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr %' OR LOWER(label) LIKE '%hr)'
),
rr_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) LIKE '%rr %'
),
spo2_items AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%oxygen saturation%' OR LOWER(label) LIKE '%oxygen sat%'
),

-- 3) a compact vitals map to join chartevents to a type label
vitals_map AS (
  SELECT itemid, 'MAP' AS vtype FROM map_items
  UNION ALL
  SELECT itemid, 'HR'  AS vtype FROM hr_items
  UNION ALL
  SELECT itemid, 'RR'  AS vtype FROM rr_items
  UNION ALL
  SELECT itemid, 'SPO2' AS vtype FROM spo2_items
),

-- 4) detect RRT stays by searching dialysis-related labels in ICU procedure/input/chart events
rrt_stays AS (
  -- procedureevents
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE pe.stay_id IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%dialysis%' OR LOWER(di.label) LIKE '%hemodialysis%' OR
      LOWER(di.label) LIKE '%crrt%' OR LOWER(di.label) LIKE '%cvvh%' OR
      LOWER(di.label) LIKE '%renal replacement%'
    )

  UNION DISTINCT

  -- inputevents (some dialysis modalities appear as inputs)
  SELECT DISTINCT ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE ie.stay_id IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%dialysis%' OR LOWER(di.label) LIKE '%hemodialysis%' OR
      LOWER(di.label) LIKE '%crrt%' OR LOWER(di.label) LIKE '%cvvh%' OR
      LOWER(di.label) LIKE '%renal replacement%'
    )

  UNION DISTINCT

  -- chartevents (sometimes modality documented in chartevents)
  SELECT DISTINCT ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE ce.stay_id IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%dialysis%' OR LOWER(di.label) LIKE '%hemodialysis%' OR
      LOWER(di.label) LIKE '%crrt%' OR LOWER(di.label) LIKE '%cvvh%' OR
      LOWER(di.label) LIKE '%renal replacement%'
    )
),

-- 5) aggregate vitals per stay in first 48 hours
vitals_per_stay AS (
  SELECT
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    icu.intime,
    icu.outtime,
    icu.los,
    -- MAP
    COUNTIF(vm.vtype = 'MAP' AND ce.valuenum IS NOT NULL) AS map_count,
    COUNTIF(vm.vtype = 'MAP' AND ce.valuenum IS NOT NULL AND ce.valuenum < 65) AS map_hyp_count,
    -- HR
    COUNTIF(vm.vtype = 'HR' AND ce.valuenum IS NOT NULL) AS hr_count,
    COUNTIF(vm.vtype = 'HR' AND ce.valuenum IS NOT NULL AND ce.valuenum > 100) AS hr_tachy_count,
    -- RR
    COUNTIF(vm.vtype = 'RR' AND ce.valuenum IS NOT NULL) AS rr_count,
    COUNTIF(vm.vtype = 'RR' AND ce.valuenum IS NOT NULL AND ce.valuenum > 24) AS rr_high_count,
    -- SpO2
    COUNTIF(vm.vtype = 'SPO2' AND ce.valuenum IS NOT NULL) AS spo2_count,
    COUNTIF(vm.vtype = 'SPO2' AND ce.valuenum IS NOT NULL AND ce.valuenum < 90) AS spo2_low_count
  FROM icu_cohort icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = icu.stay_id
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  LEFT JOIN vitals_map vm
    ON ce.itemid = vm.itemid
  GROUP BY icu.stay_id, icu.hadm_id, icu.subject_id, icu.intime, icu.outtime, icu.los
),

-- 6) combine vitals aggregates with RRT flag and admission mortality
stay_metrics AS (
  SELECT
    vps.*,
    CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag,
    -- composite score: mean of the four abnormal fractions (MAP, HR, RR, SpO2) scaled 0-100
    (
      (
        COALESCE(SAFE_DIVIDE(map_hyp_count, NULLIF(map_count, 0)), 0)
        + COALESCE(SAFE_DIVIDE(hr_tachy_count, NULLIF(hr_count, 0)), 0)
        + COALESCE(SAFE_DIVIDE(rr_high_count, NULLIF(rr_count, 0)), 0)
        + COALESCE(SAFE_DIVIDE(spo2_low_count, NULLIF(spo2_count, 0)), 0)
      ) / 4.0
    ) * 100.0 AS composite_score
  FROM vitals_per_stay vps
  LEFT JOIN rrt_stays rrt USING(stay_id)
),

-- 7) add mortality (hospital_expire_flag) from admissions for each hadm_id
stay_metrics_with_mort AS (
  SELECT sm.*,
         COALESCE(ad.hospital_expire_flag, 0) AS hospital_expire_flag
  FROM stay_metrics sm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON sm.hadm_id = ad.hadm_id
),

-- 8) compute the 90th percentile of composite among RRT stays (approximate)
rrt_composite_p90 AS (
  SELECT
    (APPROX_QUANTILES(composite_score, 100))[OFFSET(90)] AS p90_composite
  FROM stay_metrics_with_mort
  WHERE rrt_flag = 1
),

-- 9) classify stays into comparison groups:
--   - RRT_top_decile: rrt_flag = 1 AND composite_score >= p90
--   - No_RRT_all: rrt_flag = 0
classified_stays AS (
  SELECT sm.*,
    CASE
      WHEN sm.rrt_flag = 1 AND sm.composite_score >= rrt_p90.p90_composite THEN 'RRT_top_decile'
      WHEN sm.rrt_flag = 0 THEN 'No_RRT_all'
      ELSE 'RRT_other' -- not used in final comparison
    END AS group_name,
    rrt_p90.p90_composite
  FROM stay_metrics_with_mort sm
  CROSS JOIN rrt_composite_p90 rrt_p90
)

-- Final aggregated comparison for RRT_top_decile vs No_RRT_all
SELECT
  group_name,
  COUNT(*) AS n_stays,
  -- percent of stays with any MAP<65 in first 48h
  ROUND(100.0 * SUM(CASE WHEN map_hyp_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_stays_with_any_hypotension_MAP_lt_65,
  -- mean hypotension fraction (mean percent of MAP measurements <65 per stay)
  ROUND(100.0 * AVG(COALESCE(SAFE_DIVIDE(map_hyp_count, NULLIF(map_count, 0)), 0)), 2) AS mean_hypotension_fraction_pct,
  -- mean tachycardia count (mean number of HR>100 measurements per stay)
  ROUND(AVG(hr_tachy_count), 2) AS mean_tachycardia_count_per_stay,
  -- median ICU LOS in days (approximate)
  (APPROX_QUANTILES(los, 100))[OFFSET(50)] AS median_icu_los_days,
  -- hospital mortality percent
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_pct,
  -- n.b. include the p90 value for reference (same for both rows because cross joined)
  ROUND(MAX(rrt_p90), 3) AS rrt_composite_p90
FROM (
  SELECT cs.*,
         -- also expose p90 as numeric value per row for use in aggregation
         cs.p90_composite AS rrt_p90
  FROM classified_stays cs
  WHERE cs.group_name IN ('RRT_top_decile', 'No_RRT_all')
) final
GROUP BY group_name
ORDER BY group_name;