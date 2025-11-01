WITH vital_itemids AS (
  SELECT
    MAX(CASE WHEN LOWER(label) LIKE '%heart rate%' THEN itemid END) AS hr_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%systolic blood pressure%' THEN itemid END) AS sbp_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%mean blood pressure%' THEN itemid END) AS map_itemid,
    MAX(CASE WHEN LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%oxygen saturation%' THEN itemid END) AS spo2_itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
)
, cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 75 AND 85
)
, vent_stays AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.gender
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON c.stay_id = pe.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ventilat%'
    AND (LOWER(di.label) LIKE '%invasive%' OR LOWER(di.label) LIKE '%mechanical%')
)
, instability_events AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    ce.charttime,
    CASE WHEN ce.itemid = vi.hr_itemid AND ce.valuenum > 120 THEN 1 ELSE 0 END AS tachycardia,
    CASE WHEN ce.itemid = vi.sbp_itemid AND ce.valuenum < 90 THEN 1 ELSE 0 END AS hypotension_sbp,
    CASE WHEN ce.itemid = vi.map_itemid AND ce.valuenum < 65 THEN 1 ELSE 0 END AS hypotension_map,
    CASE WHEN ce.itemid = vi.spo2_itemid AND ce.valuenum < 90 THEN 1 ELSE 0 END AS hypoxemia
  FROM vent_stays vs
  CROSS JOIN vital_itemids vi
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON vs.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN vs.intime AND TIMESTAMP_ADD(vs.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (vi.hr_itemid, vi.sbp_itemid, vi.map_itemid, vi.spo2_itemid)
    AND ce.valuenum IS NOT NULL
)
, instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(tachycardia) AS tachycardia_events,
    SUM(hypotension_sbp) + SUM(hypotension_map) AS hypotension_events,
    SUM(hypoxemia) AS hypoxemia_events,
    SUM(tachycardia) + SUM(hypotension_sbp) + SUM(hypotension_map) + SUM(hypoxemia) AS composite_score
  FROM instability_events
  GROUP BY subject_id, hadm_id, stay_id
)
, scores_with_outcomes AS (
  SELECT
    isub.subject_id,
    isub.hadm_id,
    isub.stay_id,
    isub.composite_score,
    isub.tachycardia_events,
    isub.hypotension_events,
    isub.hypoxemia_events,
    vs.los,
    adm.hospital_expire_flag
  FROM instability_scores isub
  JOIN vent_stays vs
    ON isub.stay_id = vs.stay_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions adm
    ON isub.hadm_id = adm.hadm_id
)
SELECT
  -- Part 1: 90th percentile of composite instability score
  (SELECT APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] FROM scores_with_outcomes) AS composite_score_90th_percentile,

  -- Part 2: For top 25% (composite_score >= p75)
  COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)) AS n_top_25pct,
  ROUND(100 * COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)) / COUNT(*), 1) AS pct_top_25pct,

  -- Hypotension: proportion with at least one event
  ROUND(100 * COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes) AND hypotension_events > 0)
        / NULLIF(COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)), 0), 1) AS pct_hypotension_top_25pct,

  -- Tachycardia: proportion with at least one event
  ROUND(100 * COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes) AND tachycardia_events > 0)
        / NULLIF(COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)), 0), 1) AS pct_tachycardia_top_25pct,

  -- ICU LOS: median and mean
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM scores_with_outcomes
   WHERE composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)
  ) AS median_los_top_25pct,
  AVG(IF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes), los, NULL)) AS mean_los_top_25pct,

  -- Mortality: proportion expired
  ROUND(100 * COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes) AND hospital_expire_flag = 1)
        / NULLIF(COUNTIF(composite_score >= (SELECT APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] FROM scores_with_outcomes)), 0), 1) AS pct_mortality_top_25pct

FROM scores_with_outcomes;