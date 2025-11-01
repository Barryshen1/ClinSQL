WITH
-- 1) identify itemids for labs of interest (by text match in d_labitems)
lab_ids AS (
  SELECT
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%creatinine%'), ARRAY<INT64>[]) AS creat_ids,
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%potassium%' AND LOWER(label) NOT LIKE '%whole%'), ARRAY<INT64>[]) AS k_serum_ids,
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%potassium%' AND LOWER(label) LIKE '%whole%'), ARRAY<INT64>[]) AS k_whole_ids,
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%platelet%'), ARRAY<INT64>[]) AS plt_ids,
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%hemoglobin%' OR LOWER(label) LIKE '%hgb%'), ARRAY<INT64>[]) AS hgb_ids,
    COALESCE((SELECT ARRAY_AGG(itemid) FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) LIKE '%white blood cell%' OR LOWER(label) LIKE '%wbc%' OR LOWER(label) LIKE '%leukocyte%'), ARRAY<INT64>[]) AS wbc_ids
),

-- 2) cohort: male, age 68-78, admissions with a diagnosis suggesting lower GI bleeding
lowergi_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = d.icd_code AND dd.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      (
        (LOWER(COALESCE(dd.long_title, '')) LIKE '%hemorrhag%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%bleed%' OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hematochezia%')
        AND (
          LOWER(COALESCE(dd.long_title, '')) LIKE '%lower%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%rectal%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%colon%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%sigmoid%'
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%rectum%'
        )
      )
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%hematochezia%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%rectal bleeding%'
    )
),

-- 3) For each admission in the lower-GI cohort, compute binary critical flags (0/1) for each lab within 72 hours
lowergi_lab_flags AS (
  SELECT
    lga.subject_id,
    lga.hadm_id,
    lga.admittime,
    lga.dischtime,
    lga.hospital_expire_flag,
    -- creatinine critical >= 4.0
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.creat_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 4.0
    ) THEN 1 ELSE 0 END AS creat_critical,
    -- serum potassium critical <=2.5 OR >=6.5
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.k_serum_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 2.5 OR le.valuenum >= 6.5)
    ) THEN 1 ELSE 0 END AS k_serum_critical,
    -- whole-blood potassium critical <=2.5 OR >=6.5
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.k_whole_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 2.5 OR le.valuenum >= 6.5)
    ) THEN 1 ELSE 0 END AS k_whole_critical,
    -- platelets critical <= 20 (x10^3/uL)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.plt_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum <= 20
    ) THEN 1 ELSE 0 END AS plt_critical,
    -- hemoglobin critical <= 7.0 g/dL
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.hgb_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum <= 7.0
    ) THEN 1 ELSE 0 END AS hgb_critical,
    -- WBC critical <=1.0 OR >=25.0 (x10^3/uL)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = lga.hadm_id
        AND le.charttime BETWEEN lga.admittime AND TIMESTAMP_ADD(lga.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.wbc_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 1.0 OR le.valuenum >= 25.0)
    ) THEN 1 ELSE 0 END AS wbc_critical
  FROM lowergi_admissions lga
),

-- 4) compute each admission's instability score (sum of six flags)
lowergi_scores AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    creat_critical,
    k_serum_critical,
    k_whole_critical,
    plt_critical,
    hgb_critical,
    wbc_critical,
    (creat_critical + k_serum_critical + k_whole_critical + plt_critical + hgb_critical + wbc_critical) AS instability_score
  FROM lowergi_lab_flags
),

-- 5) 90th percentile threshold (approximate) -- compute once from the scores array
score_p90 AS (
  SELECT
    (SELECT quantiles[OFFSET(90)]
     FROM (
       SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
       FROM lowergi_scores
     )
    ) AS p90_score
),

-- 6) identify top-tier admissions (score >= 90th percentile)
top_tier AS (
  SELECT s.*, sp.p90_score
  FROM lowergi_scores s
  CROSS JOIN score_p90 sp
  WHERE s.instability_score >= sp.p90_score
),

-- 7) aggregate top-tier metrics
top_tier_metrics AS (
  SELECT
    COUNT(*) AS n_top,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate_top,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days_top,
    SAFE_DIVIDE(SUM(creat_critical), COUNT(*)) AS creat_crit_rate_top,
    SAFE_DIVIDE(SUM(k_serum_critical), COUNT(*)) AS k_serum_crit_rate_top,
    SAFE_DIVIDE(SUM(k_whole_critical), COUNT(*)) AS k_whole_crit_rate_top,
    SAFE_DIVIDE(SUM(plt_critical), COUNT(*)) AS plt_crit_rate_top,
    SAFE_DIVIDE(SUM(hgb_critical), COUNT(*)) AS hgb_crit_rate_top,
    SAFE_DIVIDE(SUM(wbc_critical), COUNT(*)) AS wbc_crit_rate_top
  FROM top_tier
),

-- 8) compute the same lab-critical rates across all adult inpatients (anchor_age >= 18) within first 72h
all_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age >= 18
),

all_lab_flags AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    aa.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.creat_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 4.0
    ) THEN 1 ELSE 0 END AS creat_critical,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.k_serum_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 2.5 OR le.valuenum >= 6.5)
    ) THEN 1 ELSE 0 END AS k_serum_critical,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.k_whole_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 2.5 OR le.valuenum >= 6.5)
    ) THEN 1 ELSE 0 END AS k_whole_critical,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.plt_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum <= 20
    ) THEN 1 ELSE 0 END AS plt_critical,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.hgb_ids)
        AND le.valuenum IS NOT NULL
        AND le.valuenum <= 7.0
    ) THEN 1 ELSE 0 END AS hgb_critical,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le, lab_ids
      WHERE le.hadm_id = aa.hadm_id
        AND le.charttime BETWEEN aa.admittime AND TIMESTAMP_ADD(aa.admittime, INTERVAL 72 HOUR)
        AND le.itemid IN UNNEST(lab_ids.wbc_ids)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum <= 1.0 OR le.valuenum >= 25.0)
    ) THEN 1 ELSE 0 END AS wbc_critical
  FROM all_admissions aa
),

all_metrics AS (
  SELECT
    COUNT(*) AS n_all,
    SAFE_DIVIDE(SUM(creat_critical), COUNT(*)) AS creat_crit_rate_all,
    SAFE_DIVIDE(SUM(k_serum_critical), COUNT(*)) AS k_serum_crit_rate_all,
    SAFE_DIVIDE(SUM(k_whole_critical), COUNT(*)) AS k_whole_crit_rate_all,
    SAFE_DIVIDE(SUM(plt_critical), COUNT(*)) AS plt_crit_rate_all,
    SAFE_DIVIDE(SUM(hgb_critical), COUNT(*)) AS hgb_crit_rate_all,
    SAFE_DIVIDE(SUM(wbc_critical), COUNT(*)) AS wbc_crit_rate_all
  FROM all_lab_flags
)

-- Final output: one row per reported metric with top-tier and all-inpatient columns
SELECT metric,
       CAST(top_value AS STRING) AS top_tier_value,
       CAST(all_value AS STRING) AS all_inpatients_value
FROM (
  -- p90 score
  SELECT '90th_percentile_instability_score' AS metric,
         CAST(sp.p90_score AS FLOAT64) AS top_value,
         NULL AS all_value
  FROM score_p90 sp

  UNION ALL

  -- counts
  SELECT 'n_top' AS metric,
         CAST(tm.n_top AS FLOAT64) AS top_value,
         CAST(am.n_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL

  -- mortality rate (top-tier) and blank for all (we didn't compute overall mortality here)
  SELECT 'mortality_rate_top' AS metric,
         CAST(tm.mortality_rate_top AS FLOAT64) AS top_value,
         NULL AS all_value
  FROM top_tier_metrics tm

  UNION ALL

  -- average LOS (days) for top-tier
  SELECT 'avg_los_days_top' AS metric,
         CAST(tm.avg_los_days_top AS FLOAT64) AS top_value,
         NULL AS all_value
  FROM top_tier_metrics tm

  UNION ALL

  -- Lab critical rates: for each lab, show top-tier and all-inpatients rate
  SELECT 'creatinine_crit_rate' AS metric,
         CAST(tm.creat_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.creat_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL
  SELECT 'serum_potassium_crit_rate' AS metric,
         CAST(tm.k_serum_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.k_serum_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL
  SELECT 'whole_blood_potassium_crit_rate' AS metric,
         CAST(tm.k_whole_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.k_whole_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL
  SELECT 'platelets_crit_rate' AS metric,
         CAST(tm.plt_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.plt_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL
  SELECT 'hemoglobin_crit_rate' AS metric,
         CAST(tm.hgb_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.hgb_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am

  UNION ALL
  SELECT 'wbc_crit_rate' AS metric,
         CAST(tm.wbc_crit_rate_top AS FLOAT64) AS top_value,
         CAST(am.wbc_crit_rate_all AS FLOAT64) AS all_value
  FROM top_tier_metrics tm CROSS JOIN all_metrics am
)
ORDER BY metric;