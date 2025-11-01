WITH
-- Get MAP and HR itemids
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%' AND LOWER(category) LIKE '%vital%'
),
hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%' AND LOWER(category) LIKE '%vital%'
),

-- Identify shock ICD codes (ICD-9: 785.5*, ICD-10: R57*)
shock_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code LIKE '7855%')
     OR (icd_version = 10 AND icd_code LIKE 'R57%')
),

-- ICU stays for women aged 59-69
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender,
    pat.dod
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
),

-- Shock diagnosis flag per ICU stay
shock_flag AS (
  SELECT
    c.stay_id,
    CASE WHEN COUNT(s.icd_code) > 0 THEN 1 ELSE 0 END AS shock
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN shock_icds s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  GROUP BY c.stay_id
),

-- MAP measurements in first 24h
map_events AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- HR measurements in first 24h
hr_events AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN hr_items hi
    ON ce.itemid = hi.itemid
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate hypotension and tachycardia burden per stay
instability AS (
  SELECT
    c.stay_id,
    -- Hypotension burden: % MAP < 65
    SAFE_DIVIDE(SUM(CASE WHEN me.valuenum < 65 THEN 1 ELSE 0 END), COUNT(me.valuenum)) AS hypotension_burden,
    -- Tachycardia burden: % HR > 100
    SAFE_DIVIDE(SUM(CASE WHEN he.valuenum > 100 THEN 1 ELSE 0 END), COUNT(he.valuenum)) AS tachycardia_burden
  FROM cohort c
  LEFT JOIN map_events me ON c.stay_id = me.stay_id
  LEFT JOIN hr_events he ON c.stay_id = he.stay_id
  GROUP BY c.stay_id
),

-- Composite instability score: mean of hypotension and tachycardia burden
instability_score AS (
  SELECT
    i.stay_id,
    i.hypotension_burden,
    i.tachycardia_burden,
    SAFE_DIVIDE(i.hypotension_burden + i.tachycardia_burden, 2) AS composite_instability_score
  FROM instability i
),

-- ICU mortality: death during ICU stay
icu_mortality AS (
  SELECT
    c.stay_id,
    CASE
      WHEN c.dod IS NOT NULL AND c.dod >= c.intime AND c.dod <= c.outtime THEN 1
      ELSE 0
    END AS icu_death
  FROM cohort c
),

-- Final per-stay summary
per_stay AS (
  SELECT
    c.stay_id,
    sf.shock,
    iscore.composite_instability_score,
    iscore.hypotension_burden,
    iscore.tachycardia_burden,
    c.los,
    im.icu_death
  FROM cohort c
  LEFT JOIN shock_flag sf ON c.stay_id = sf.stay_id
  LEFT JOIN instability_score iscore ON c.stay_id = iscore.stay_id
  LEFT JOIN icu_mortality im ON c.stay_id = im.stay_id
)

-- Aggregate statistics by shock group
SELECT
  CASE WHEN shock = 1 THEN 'Shock' ELSE 'No Shock' END AS shock_group,
  COUNT(*) AS n_stays,
  -- Composite instability score
  AVG(composite_instability_score) AS mean_composite_instability_score,
  APPROX_QUANTILES(composite_instability_score, 100)[25] AS p25_composite_instability_score,
  APPROX_QUANTILES(composite_instability_score, 100)[50] AS p50_composite_instability_score,
  APPROX_QUANTILES(composite_instability_score, 100)[75] AS p75_composite_instability_score,
  APPROX_QUANTILES(composite_instability_score, 100)[90] AS p90_composite_instability_score,
  -- Hypotension burden
  AVG(hypotension_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[25] AS p25_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[50] AS p50_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[75] AS p75_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[90] AS p90_hypotension_burden,
  -- Tachycardia burden
  AVG(tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[25] AS p25_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[50] AS p50_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[75] AS p75_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[90] AS p90_tachycardia_burden,
  -- ICU LOS
  AVG(los) AS mean_icu_los,
  APPROX_QUANTILES(los, 100)[25] AS p25_icu_los,
  APPROX_QUANTILES(los, 100)[50] AS p50_icu_los,
  APPROX_QUANTILES(los, 100)[75] AS p75_icu_los,
  APPROX_QUANTILES(los, 100)[90] AS p90_icu_los,
  -- ICU mortality
  AVG(icu_death) AS icu_mortality_rate
FROM per_stay
GROUP BY shock
ORDER BY shock DESC;