WITH
-- common d_items for ICU chartevents / procedureevents lookup
d_items_icu AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
),

-- Identify stays with RRT by looking for procedureevents whose d_items.label mentions dialysis/RRT keywords
rrt_stays AS (
  SELECT DISTINCT pe.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN d_items_icu di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%dialysis%'
     OR di.label LIKE '%hemodialysis%'
     OR di.label LIKE '%hemofiltration%'
     OR di.label LIKE '%continuous renal%'
     OR di.label LIKE '%renal replacement%'
     OR di.label LIKE '%crrt%'
),

-- Aggregate worst vitals in the first 72 hours per ICU stay
per_stay_vitals AS (
  SELECT
    ic.stay_id,
    ic.subject_id,
    ic.hadm_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.anchor_age,
    p.gender,
    adm.hospital_expire_flag,
    -- worst values in first 72 hours (HR max, RR max, SBP min)
    MAX(CASE WHEN di.label LIKE '%heart rate%' THEN ce.valuenum END) AS hr_max,
    MAX(CASE WHEN di.label LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr_max,
    MIN(CASE WHEN di.label LIKE '%systolic%' AND di.label LIKE '%bp%' THEN ce.valuenum END) AS sbp_min
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    USING(hadm_id)
  -- join chartevents within the first 72 hours of ICU stay
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = ic.stay_id
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
  LEFT JOIN d_items_icu di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
  GROUP BY ic.stay_id, ic.subject_id, ic.hadm_id, ic.intime, ic.outtime, ic.los, p.anchor_age, p.gender, adm.hospital_expire_flag
),

-- Keep only stays that had RRT and have at least one vital component to compute a score
cohort_scores AS (
  SELECT
    v.*,
    -- normalized components (bounded to 0-100). Nulls left as NULL.
    -- HR normalization: map 40..180 -> 0..100 (higher HR worse)
    CASE
      WHEN hr_max IS NULL THEN NULL
      ELSE LEAST(GREATEST((hr_max - 40) / (180 - 40) * 100.0, 0.0), 100.0)
    END AS hr_norm,
    -- RR normalization: map 5..60 -> 0..100 (higher RR worse)
    CASE
      WHEN rr_max IS NULL THEN NULL
      ELSE LEAST(GREATEST((rr_max - 5) / (60 - 5) * 100.0, 0.0), 100.0)
    END AS rr_norm,
    -- SBP normalization: lower SBP worse; map SBP_min 120..40 -> 0..100 (so SBP_min >=120 -> 0, SBP_min=40 ->100)
    CASE
      WHEN sbp_min IS NULL THEN NULL
      ELSE LEAST(GREATEST((120.0 - sbp_min) / (120.0 - 40.0) * 100.0, 0.0), 100.0)
    END AS sbp_norm
  FROM per_stay_vitals v
  JOIN rrt_stays r ON v.stay_id = r.stay_id
),

-- compute composite instability score and restrict to stays where at least one component is present
scores AS (
  SELECT
    cs.stay_id,
    cs.subject_id,
    cs.hadm_id,
    cs.anchor_age,
    cs.gender,
    cs.los,
    cs.hospital_expire_flag,
    cs.hr_max,
    cs.rr_max,
    cs.sbp_min,
    cs.hr_norm,
    cs.rr_norm,
    cs.sbp_norm,
    -- Composite score: weights 0.4 (HR), 0.3 (RR), 0.3 (SBP).
    -- If a component is NULL we treat it as 0 contribution but also count only stays with at least one non-null component.
    ROUND( (COALESCE(cs.hr_norm, 0.0) * 0.4
          + COALESCE(cs.rr_norm, 0.0) * 0.3
          + COALESCE(cs.sbp_norm, 0.0) * 0.3), 2) AS instability_score,
    -- flag to ensure at least one vital was present
    (CASE WHEN cs.hr_max IS NOT NULL OR cs.rr_max IS NOT NULL OR cs.sbp_min IS NOT NULL THEN 1 ELSE 0 END) AS has_vitals
  FROM cohort_scores cs
),

-- compute 75th percentile cutoff (scalar) for stays with a valid score
quartiles AS (
  SELECT (APPROX_QUANTILES(instability_score, 4))[OFFSET(3)] AS quartile_75
  FROM scores
  WHERE has_vitals = 1
)

-- Final analytics: percentile of a score value (85) and outcomes for most unstable quartile
SELECT
  cohort_total,
  cohort_with_score,
  -- percentile: percent of cohort whose instability_score <= 85
  ROUND(100.0 * SAFE_DIVIDE(count_le_85, cohort_with_score), 2) AS percentile_of_85,
  -- cutoff for the top (most unstable) quartile (75th percentile)
  ROUND((SELECT quartile_75 FROM quartiles), 2) AS quartile_75_cutoff,
  quartile_count,
  ROUND(quartile_avg_icu_los, 2) AS quartile_avg_icu_los_days,
  ROUND(100.0 * quartile_hosp_mortality, 2) AS quartile_hospital_mortality_percent
FROM (
  SELECT
    COUNT(*) AS cohort_total,
    SUM(has_vitals) AS cohort_with_score,
    SUM(CASE WHEN has_vitals = 1 AND instability_score <= 85 THEN 1 ELSE 0 END) AS count_le_85,
    -- quartile metrics computed via scalar subqueries referencing quartile_75
    (SELECT COUNT(*) FROM scores s2 WHERE s2.has_vitals = 1 AND s2.instability_score >= (SELECT quartile_75 FROM quartiles)) AS quartile_count,
    (SELECT AVG(s2.los) FROM scores s2 WHERE s2.has_vitals = 1 AND s2.instability_score >= (SELECT quartile_75 FROM quartiles)) AS quartile_avg_icu_los,
    (SELECT SAFE_DIVIDE(SUM(s2.hospital_expire_flag), COUNT(*))
     FROM scores s2
     WHERE s2.has_vitals = 1 AND s2.instability_score >= (SELECT quartile_75 FROM quartiles)
    ) AS quartile_hosp_mortality
  FROM scores
) ;