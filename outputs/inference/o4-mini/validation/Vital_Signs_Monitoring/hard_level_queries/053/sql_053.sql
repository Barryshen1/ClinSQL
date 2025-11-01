WITH shock_adms AS (
  -- Admissions with any ICD diagnosis containing 'shock'
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%shock%'
),
vital_events AS (
  -- Extract MAP and Heart Rate events
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    di.label,
    ce.valuenum,
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label IN ('MAP', 'Mean Arterial Pressure', 'Heart Rate')
),
metrics_per_stay AS (
  -- Compute burdens and composite instability per ICU stay
  SELECT
    vs.stay_id,
    icu.subject_id,
    icu.hadm_id,
    -- hypotension burden
    SAFE_DIVIDE(
      SUM(CASE WHEN LOWER(vs.label) LIKE '%map%' AND vs.valuenum < 65 THEN 1 ELSE 0 END),
      SUM(CASE WHEN LOWER(vs.label) LIKE '%map%' THEN 1 ELSE 0 END)
    ) AS hypo_burden,
    -- tachycardia burden
    SAFE_DIVIDE(
      SUM(CASE WHEN vs.label = 'Heart Rate' AND vs.valuenum > 100 THEN 1 ELSE 0 END),
      SUM(CASE WHEN vs.label = 'Heart Rate' THEN 1 ELSE 0 END)
    ) AS tachy_burden,
    -- composite instability
    SAFE_CAST(
      SAFE_DIVIDE(
        SUM(CASE WHEN LOWER(vs.label) LIKE '%map%' AND vs.valuenum < 65 THEN 1 ELSE 0 END),
        SUM(CASE WHEN LOWER(vs.label) LIKE '%map%' THEN 1 ELSE 0 END)
      )
      +
      SAFE_DIVIDE(
        SUM(CASE WHEN vs.label = 'Heart Rate' AND vs.valuenum > 100 THEN 1 ELSE 0 END),
        SUM(CASE WHEN vs.label = 'Heart Rate' THEN 1 ELSE 0 END)
      )
    AS FLOAT64) AS composite_instability
  FROM vital_events vs
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON vs.subject_id = icu.subject_id
   AND vs.hadm_id    = icu.hadm_id
   AND vs.stay_id    = icu.stay_id
  WHERE vs.charttime >= icu.intime
    AND vs.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY vs.stay_id, icu.subject_id, icu.hadm_id
),
stay_enriched AS (
  -- Combine metrics with demographics, LOS, mortality, and shock flag
  SELECT
    m.stay_id,
    p.anchor_age,
    p.gender,
    m.hypo_burden,
    m.tachy_burden,
    m.composite_instability,
    icu.los,
    adm.hospital_expire_flag AS mortality,
    COALESCE(s.shock_flag, 0) AS shock_flag
  FROM metrics_per_stay m
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON m.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON m.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON m.hadm_id = adm.hadm_id
  LEFT JOIN shock_adms s
    ON m.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
)
SELECT
  shock_flag,
  -- Composite instability
  AVG(composite_instability)                                             AS mean_composite,
  APPROX_QUANTILES(composite_instability, 4)[OFFSET(1)]                   AS p25_composite,
  APPROX_QUANTILES(composite_instability, 4)[OFFSET(2)]                   AS p50_composite,
  APPROX_QUANTILES(composite_instability, 4)[OFFSET(3)]                   AS p75_composite,
  -- Hypotension burden
  AVG(hypo_burden)                                                        AS mean_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(1)]                             AS p25_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(2)]                             AS p50_hypotension_burden,
  APPROX_QUANTILES(hypo_burden, 4)[OFFSET(3)]                             AS p75_hypotension_burden,
  -- Tachycardia burden
  AVG(tachy_burden)                                                       AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(1)]                            AS p25_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(2)]                            AS p50_tachycardia_burden,
  APPROX_QUANTILES(tachy_burden, 4)[OFFSET(3)]                            AS p75_tachycardia_burden,
  -- ICU length of stay
  AVG(los)                                                                AS mean_icu_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)]                                     AS p25_icu_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)]                                     AS p50_icu_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)]                                     AS p75_icu_los,
  -- Mortality
  AVG(mortality)                                                          AS mortality_rate
FROM stay_enriched
GROUP BY shock_flag
ORDER BY shock_flag;