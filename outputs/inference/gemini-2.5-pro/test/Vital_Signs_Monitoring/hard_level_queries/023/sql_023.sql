WITH
cohort AS (
  -- Step 1: Identify the cohort of male ICU patients aged 55-65.
  -- Then, classify them into 'HFNC' or 'Control' groups based on whether they received
  -- High-Flow Nasal Cannula within the first 24 hours of their ICU stay.
  SELECT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    CASE
      WHEN hfn.stay_id IS NOT NULL THEN 'HFNC'
      ELSE 'Control'
    END AS hfn_group
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  LEFT JOIN (
    -- Subquery to find ICU stays where HFNC was administered in the first 24 hours
    SELECT DISTINCT
      ce.stay_id
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON ce.stay_id = icu.stay_id
    WHERE
      ce.itemid = 226732 -- O2 Delivery Device(s)
      AND ce.value IN ('High Flow Nasal Cannula', 'HFNC', 'High flow neb')
      AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  ) AS hfn
    ON icu.stay_id = hfn.stay_id
  WHERE
    p.gender = 'M'
    -- Calculate age at the time of ICU admission
    AND (p.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 55 AND 65
),
vitals_pivot AS (
  -- Step 2: Pivot chartevents to get raw vital signs (HR, RR, MAP) for our cohort.
  -- This aligns measurements taken at the same time into a single row.
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS rr,
    MAX(CASE WHEN ce.itemid = 220052 THEN ce.valuenum END) AS map_invasive,
    MAX(CASE WHEN ce.itemid = 220181 THEN ce.valuenum END) AS map_nibp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.stay_id IN (
      SELECT stay_id FROM cohort
    )
    AND ce.itemid IN (220045, 220210, 220052, 220181) -- HR, RR, Arterial MAP, NIBP MAP
  GROUP BY
    ce.stay_id,
    ce.charttime
),
vitals AS (
  -- Step 3: Clean and combine the pivoted vital signs.
  -- We prefer invasive MAP (map_invasive) but will use non-invasive (map_nibp) if it's not available.
  -- Basic data cleaning is applied to remove implausible values.
  SELECT
    vp.stay_id,
    c.hfn_group,
    vp.hr,
    vp.rr,
    COALESCE(vp.map_invasive, vp.map_nibp) AS map
  FROM
    vitals_pivot AS vp
  INNER JOIN
    cohort AS c
    ON vp.stay_id = c.stay_id
  WHERE
    -- Data cleaning for plausible physiological ranges
    (vp.hr > 0 AND vp.hr < 300)
    AND (vp.rr > 0 AND vp.rr < 70)
    AND (COALESCE(vp.map_invasive, vp.map_nibp) > 0 AND COALESCE(vp.map_invasive, vp.map_nibp) < 250)
),
instability_scores AS (
  -- Step 4: Calculate an instability score for each valid set of vitals.
  -- The score is the sum of the absolute z-scores for HR, RR, and MAP.
  -- We use clinically reasonable population means and standard deviations for z-scoring.
  SELECT
    v.hfn_group,
    -- Instability Score = |z(HR)| + |z(RR)| + |z(MAP)| where z(x) = (x - mean) / stddev
    -- Assumed means/stddevs: HR(80, 20), RR(16, 5), MAP(80, 15)
    ABS((v.hr - 80) / 20) + ABS((v.rr - 16) / 5) + ABS((v.map - 80) / 15) AS instability_score
  FROM
    vitals AS v
  WHERE
    v.hr IS NOT NULL AND v.rr IS NOT NULL AND v.map IS NOT NULL
),
patient_burdens AS (
  -- Step 5: Calculate per-patient burdens for tachycardia and hypotension.
  -- Burden is defined as the fraction of measurements that fall outside the normal range.
  SELECT
    v.stay_id,
    v.hfn_group,
    -- Tachycardia: HR > 100 bpm
    SAFE_DIVIDE(SUM(CASE WHEN v.hr > 100 THEN 1 ELSE 0 END), COUNT(v.hr)) AS tachycardia_burden,
    -- Hypotension: MAP < 65 mmHg
    SAFE_DIVIDE(SUM(CASE WHEN v.map < 65 THEN 1 ELSE 0 END), COUNT(v.map)) AS hypotension_burden
  FROM
    vitals AS v
  GROUP BY
    v.stay_id,
    v.hfn_group
),
-- Step 6: Aggregate the calculated metrics for each group ('HFNC' vs 'Control').
instability_agg AS (
  -- Aggregate all instability scores to find the group-level percentiles.
  SELECT
    hfn_group,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS instability_p25,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS instability_median,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS instability_p75,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS instability_p95
  FROM
    instability_scores
  GROUP BY
    hfn_group
),
burden_agg AS (
  -- Average the per-patient burdens to get the group-level average burden.
  SELECT
    hfn_group,
    AVG(tachycardia_burden) AS avg_tachycardia_burden,
    AVG(hypotension_burden) AS avg_hypotension_burden
  FROM
    patient_burdens
  GROUP BY
    hfn_group
),
outcome_agg AS (
  -- Calculate group-level averages for LOS, mortality, and patient counts.
  SELECT
    c.hfn_group,
    AVG(c.los) AS avg_icu_los_days,
    AVG(adm.hospital_expire_flag) AS hospital_mortality_rate,
    COUNT(DISTINCT c.stay_id) AS number_of_patients
  FROM
    cohort AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON c.hadm_id = adm.hadm_id
  GROUP BY
    c.hfn_group
)
-- Step 7: Final assembly.
-- Join the aggregated results for each metric into a final report.
SELECT
  oa.hfn_group,
  oa.number_of_patients,
  ia.instability_median,
  ia.instability_p25,
  ia.instability_p75,
  ia.instability_p95,
  ba.avg_tachycardia_burden,
  ba.avg_hypotension_burden,
  oa.avg_icu_los_days,
  oa.hospital_mortality_rate
FROM
  outcome_agg AS oa
LEFT JOIN
  instability_agg AS ia
  ON oa.hfn_group = ia.hfn_group
LEFT JOIN
  burden_agg AS ba
  ON oa.hfn_group = ba.hfn_group
ORDER BY
  oa.hfn_group;