WITH hfnc_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow%' OR LOWER(label) LIKE '%hfnc%' OR LOWER(label) LIKE '%nasal cannula%'
),

-- Step 2: Identify HR and SBP itemids
hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic blood pressure%'
),

-- Step 3: Build base ICU cohort (male, age 55-65)
base_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
),

-- Step 4: HFNC within 24h of ICU admission (FIXED: join icustays for intime)
hfnc_first24h AS (
  SELECT DISTINCT
    c.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN hfnc_items hi ON c.itemid = hi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.stay_id = icu.stay_id
  WHERE TIMESTAMP_DIFF(c.charttime, icu.intime, HOUR) BETWEEN 0 AND 24
),

-- Step 5: Label cohort as HFNC or control
labeled_cohort AS (
  SELECT
    bc.*,
    CASE WHEN hfnc.stay_id IS NOT NULL THEN 'HFNC' ELSE 'Control' END AS group_type
  FROM base_cohort bc
  LEFT JOIN hfnc_first24h hfnc
    ON bc.stay_id = hfnc.stay_id
),

-- Step 6: Get HR and SBP measurements in first 24h
vitals_first24h AS (
  SELECT
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN labeled_cohort lc ON c.stay_id = lc.stay_id
  WHERE TIMESTAMP_DIFF(c.charttime, lc.intime, HOUR) BETWEEN 0 AND 24
    AND c.valuenum IS NOT NULL
    AND (
      c.itemid IN (SELECT itemid FROM hr_items)
      OR c.itemid IN (SELECT itemid FROM sbp_items)
    )
),

-- Step 7: Compute instability, tachycardia, hypotension burden per stay
instability_per_stay AS (
  SELECT
    lc.stay_id,
    lc.group_type,
    lc.los,
    lc.subject_id,
    lc.hadm_id,
    -- Mortality flag
    CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality,
    -- Instability score: number of hours in first 24h with tachycardia or hypotension
    COUNT(DISTINCT CASE WHEN (hr.hr > 100 OR sbp.sbp < 90) THEN EXTRACT(HOUR FROM v.charttime) END) AS instability_score,
    -- Tachycardia burden: number of measurements with HR > 100
    COUNT(DISTINCT CASE WHEN hr.hr > 100 THEN v.charttime END) AS tachycardia_burden,
    -- Hypotension burden: number of measurements with SBP < 90
    COUNT(DISTINCT CASE WHEN sbp.sbp < 90 THEN v.charttime END) AS hypotension_burden
  FROM labeled_cohort lc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON lc.hadm_id = adm.hadm_id
  LEFT JOIN (
    SELECT stay_id, charttime, MAX(valuenum) AS hr
    FROM vitals_first24h
    WHERE itemid IN (SELECT itemid FROM hr_items)
    GROUP BY stay_id, charttime
  ) hr
    ON lc.stay_id = hr.stay_id AND hr.charttime IS NOT NULL
  LEFT JOIN (
    SELECT stay_id, charttime, MAX(valuenum) AS sbp
    FROM vitals_first24h
    WHERE itemid IN (SELECT itemid FROM sbp_items)
    GROUP BY stay_id, charttime
  ) sbp
    ON lc.stay_id = sbp.stay_id AND sbp.charttime IS NOT NULL
  LEFT JOIN vitals_first24h v
    ON lc.stay_id = v.stay_id AND v.charttime IS NOT NULL
  GROUP BY lc.stay_id, lc.group_type, lc.los, lc.subject_id, lc.hadm_id, adm.hospital_expire_flag
),

-- Step 8: Compute statistics per group
stats AS (
  SELECT
    group_type,
    COUNT(*) AS n_stays,
    -- Instability score stats
    APPROX_QUANTILES(instability_score, 100)[50] AS instability_median,
    APPROX_QUANTILES(instability_score, 100)[25] AS instability_p25,
    APPROX_QUANTILES(instability_score, 100)[75] AS instability_p75,
    APPROX_QUANTILES(instability_score, 100)[95] AS instability_p95,
    -- Tachycardia burden stats
    APPROX_QUANTILES(tachycardia_burden, 100)[50] AS tachycardia_median,
    -- Hypotension burden stats
    APPROX_QUANTILES(hypotension_burden, 100)[50] AS hypotension_median,
    -- ICU LOS stats
    APPROX_QUANTILES(los, 100)[50] AS icu_los_median,
    -- Mortality rate
    AVG(mortality) AS mortality_rate
  FROM instability_per_stay
  GROUP BY group_type
)

SELECT * FROM stats
ORDER BY group_type;