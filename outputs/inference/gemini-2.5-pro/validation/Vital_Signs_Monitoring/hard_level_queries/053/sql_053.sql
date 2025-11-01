WITH
cohort_stays AS (
  -- Step 1: Define the base cohort of ICU stays for female patients aged 59-69.
  -- This CTE gathers essential identifiers and outcomes like LOS and mortality.
  SELECT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    -- Calculate age at ICU admission
    AND (EXTRACT(YEAR FROM icu.intime) - p.anchor_year + p.anchor_age) BETWEEN 59 AND 69
),
shock_cohort AS (
  -- Step 2: Stratify the cohort into 'Shock' and 'No Shock' groups.
  -- A flag is created if a patient has any shock-related ICD code for their admission.
  SELECT
    cs.stay_id,
    cs.intime,
    cs.los,
    cs.hospital_expire_flag,
    MAX(CASE WHEN diag.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS shock_group_flag
  FROM
    cohort_stays AS cs
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for shock start with '7855' (e.g., 785.51 -> 78551)
      (icd_version = 9 AND icd_code LIKE '7855%')
      -- ICD-10 codes for shock
      OR (icd_version = 10 AND (icd_code LIKE 'R57%' OR icd_code = 'R6521'))
  ) AS diag
    ON cs.hadm_id = diag.hadm_id
  GROUP BY
    cs.stay_id,
    cs.intime,
    cs.los,
    cs.hospital_expire_flag
),
vitals_intervals AS (
  -- Step 3: Reconstruct continuous vital signs and calculate the duration of each state.
  WITH
  vitals_ff AS (
    -- This sub-CTE pivots and forward-fills HR and MAP values.
    SELECT
      stay_id,
      charttime,
      -- Carry forward the last known value for HR and MAP
      LAST_VALUE(hr IGNORE NULLS) OVER w AS hr_ff,
      LAST_VALUE(map IGNORE NULLS) OVER w AS map_ff
    FROM
      (
        -- This sub-CTE extracts and pivots raw HR and MAP measurements
        SELECT
          sc.stay_id,
          ce.charttime,
          AVG(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr,
          AVG(CASE WHEN ce.itemid IN (220052, 220181, 225312) THEN ce.valuenum END) AS map
        FROM
          `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        INNER JOIN shock_cohort AS sc
          ON ce.stay_id = sc.stay_id
        WHERE
          -- Filter for the first 24 hours of the ICU stay
          ce.charttime BETWEEN sc.intime AND DATETIME_ADD(sc.intime, INTERVAL 24 HOUR)
          AND ce.itemid IN (
            220045, -- Heart Rate
            220052, -- Arterial Blood Pressure mean
            220181, -- Non Invasive Blood Pressure mean
            225312  -- ART BP mean
          )
          AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
        GROUP BY
          sc.stay_id, ce.charttime
      )
    WINDOW
      w AS (PARTITION BY stay_id ORDER BY charttime ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  )
  -- Calculate the duration (in minutes) for which each forward-filled state is valid.
  SELECT
    v.stay_id,
    v.hr_ff,
    v.map_ff,
    DATETIME_DIFF(
      COALESCE(
        LEAD(v.charttime, 1) OVER (PARTITION BY v.stay_id ORDER BY v.charttime),
        DATETIME_ADD(sc.intime, INTERVAL 24 HOUR)
      ),
      v.charttime,
      MINUTE
    ) AS duration_minutes
  FROM
    vitals_ff AS v
  INNER JOIN shock_cohort AS sc
    ON v.stay_id = sc.stay_id
  -- Only include intervals where we have a valid value for both HR and MAP
  WHERE
    v.hr_ff IS NOT NULL AND v.map_ff IS NOT NULL
),
burdens AS (
  -- Step 4: Calculate the final burden scores for each stay.
  SELECT
    stay_id,
    -- Hypotension: Proportion of time with MAP < 65
    SAFE_DIVIDE(SUM(IF(map_ff < 65, duration_minutes, 0)), SUM(duration_minutes)) AS hypotension_burden,
    -- Tachycardia: Proportion of time with HR > 100
    SAFE_DIVIDE(SUM(IF(hr_ff > 100, duration_minutes, 0)), SUM(duration_minutes)) AS tachycardia_burden,
    -- Instability: Proportion of time with either hypotension OR tachycardia
    SAFE_DIVIDE(SUM(IF(map_ff < 65 OR hr_ff > 100, duration_minutes, 0)), SUM(duration_minutes)) AS composite_instability_score
  FROM
    vitals_intervals
  WHERE duration_minutes > 0
  GROUP BY
    stay_id
)
-- Step 5: Final aggregation and presentation of results.
SELECT
  CASE
    WHEN sc.shock_group_flag = 1 THEN 'Shock'
    ELSE 'No Shock'
  END AS shock_group,
  COUNT(DISTINCT sc.stay_id) AS number_of_stays,

  -- Composite Instability Score
  AVG(b.composite_instability_score) AS mean_instability_score,
  APPROX_QUANTILES(b.composite_instability_score, 100)[OFFSET(25)] AS p25_instability_score,
  APPROX_QUANTILES(b.composite_instability_score, 100)[OFFSET(50)] AS p50_instability_score,
  APPROX_QUANTILES(b.composite_instability_score, 100)[OFFSET(75)] AS p75_instability_score,

  -- Hypotension Burden
  AVG(b.hypotension_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(b.hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension_burden,
  APPROX_QUANTILES(b.hypotension_burden, 100)[OFFSET(50)] AS p50_hypotension_burden,
  APPROX_QUANTILES(b.hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension_burden,

  -- Tachycardia Burden
  AVG(b.tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(b.tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia_burden,
  APPROX_QUANTILES(b.tachycardia_burden, 100)[OFFSET(50)] AS p50_tachycardia_burden,
  APPROX_QUANTILES(b.tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia_burden,

  -- ICU LOS
  AVG(sc.los) AS mean_icu_los_days,
  APPROX_QUANTILES(sc.los, 100)[OFFSET(25)] AS p25_icu_los_days,
  APPROX_QUANTILES(sc.los, 100)[OFFSET(50)] AS p50_icu_los_days,
  APPROX_QUANTILES(sc.los, 100)[OFFSET(75)] AS p75_icu_los_days,

  -- Mortality
  AVG(sc.hospital_expire_flag) AS hospital_mortality_rate
FROM
  shock_cohort AS sc
LEFT JOIN burdens AS b
  ON sc.stay_id = b.stay_id
GROUP BY
  shock_group
ORDER BY
  shock_group DESC;