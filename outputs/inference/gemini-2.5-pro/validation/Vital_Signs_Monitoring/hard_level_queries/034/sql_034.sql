WITH
-- Step 1: Define the cohort of ICU stays for female patients aged 60-70 with mixed shock.
cohort_stays AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) + pat.anchor_age BETWEEN 60 AND 70
    -- Use 'Other shock' as a proxy for 'Mixed Shock'
    AND dx.icd_code IN ('78559', 'R578') -- ICD-9: 785.59, ICD-10: R57.8
),

-- Step 2: Get the first charted weight for each ICU stay to normalize drug doses.
weights AS (
  SELECT
    stay_id,
    patientweight AS weight
  FROM (
    SELECT
      stay_id,
      patientweight,
      ROW_NUMBER() OVER(PARTITION BY stay_id ORDER BY starttime) as rn
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE patientweight IS NOT NULL AND patientweight > 0
  )
  WHERE rn = 1
),

-- Step 3: Calculate norepinephrine-equivalent dose for all vasopressors in the first 48h.
vaso_doses AS (
  SELECT
    cs.stay_id,
    -- Calculate norepinephrine equivalent dose in mcg/kg/min
    CASE
      -- Norepinephrine, Epinephrine, Phenylephrine (mcg/kg/min) - No conversion needed
      WHEN ie.itemid IN (221906, 221289, 221749) AND ie.rateuom = 'mcg/kg/min' THEN ie.rate
      -- Phenylephrine (mcg/min) -> mcg/kg/min
      WHEN ie.itemid = 221749 AND ie.rateuom = 'mcg/min' AND w.weight IS NOT NULL THEN ie.rate / w.weight
      -- Dopamine, Dobutamine (mcg/kg/min) -> NE equivalent
      WHEN ie.itemid IN (221662, 221653) AND ie.rateuom = 'mcg/kg/min' THEN ie.rate / 100
      -- Vasopressin (units/min or units/hour) -> NE equivalent
      WHEN ie.itemid = 222315 AND ie.rateuom = 'units/min' THEN ie.rate * 2.5
      WHEN ie.itemid = 222315 AND ie.rateuom = 'units/hour' THEN (ie.rate / 60) * 2.5
      ELSE NULL
    END AS ne_dose
  FROM cohort_stays AS cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON cs.stay_id = ie.stay_id
  LEFT JOIN weights AS w
    ON cs.stay_id = w.stay_id
  WHERE
    ie.starttime <= DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    AND ie.itemid IN (
      221906, -- Norepinephrine
      221289, -- Epinephrine
      221749, -- Phenylephrine
      221662, -- Dopamine
      222315, -- Vasopressin
      221653  -- Dobutamine
    )
    AND ie.rate IS NOT NULL AND ie.rate > 0
),

-- Step 4: Calculate the instability score (max NE dose) for each patient and assign deciles.
instability_scores AS (
  SELECT
    cs.stay_id,
    cs.los,
    cs.hospital_expire_flag,
    COALESCE(MAX(vd.ne_dose), 0) AS instability_score,
    NTILE(10) OVER (ORDER BY COALESCE(MAX(vd.ne_dose), 0) DESC) AS instability_decile
  FROM cohort_stays AS cs
  LEFT JOIN vaso_doses AS vd
    ON cs.stay_id = vd.stay_id
  GROUP BY
    cs.stay_id, cs.los, cs.hospital_expire_flag
),

-- Step 5: Calculate proportion of hypotensive MAP readings (<65) in the first 48h.
map_data AS (
  SELECT
    cs.stay_id,
    AVG(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS proportion_hypotensive
  FROM cohort_stays AS cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (220052, 220181) -- MAP (Invasive, Non-invasive)
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
  GROUP BY cs.stay_id
),

-- Step 6: Calculate max heart rate in the first 48h.
tachy_data AS (
  SELECT
    cs.stay_id,
    MAX(ce.valuenum) AS max_tachycardia
  FROM cohort_stays AS cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    AND ce.itemid = 220045 -- Heart Rate
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0
  GROUP BY cs.stay_id
),

-- Step 7: Combine all metrics into a single table per stay.
all_metrics AS (
  SELECT
    i_s.stay_id,
    i_s.instability_score,
    i_s.instability_decile,
    COALESCE(md.proportion_hypotensive, 0) AS proportion_hypotensive,
    t_d.max_tachycardia,
    i_s.los AS icu_los,
    i_s.hospital_expire_flag
  FROM instability_scores AS i_s
  LEFT JOIN map_data AS md
    ON i_s.stay_id = md.stay_id
  LEFT JOIN tachy_data AS t_d
    ON i_s.stay_id = t_d.stay_id
)

-- Final Step: Present the results in a readable format.
-- Part 1: 95th percentile instability score for the cohort.
SELECT
  'Cohort 95th-percentile instability score (max NE dose mcg/kg/min)' AS metric,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS value
FROM all_metrics

UNION ALL

-- Part 2: Compare top decile vs. the entire cohort on key metrics.
SELECT '--- Comparison Metrics ---' AS metric, CAST(NULL AS FLOAT64) AS value
UNION ALL
SELECT 'N Patients in Top Decile' AS metric, CAST(COUNT(stay_id) AS FLOAT64) FROM all_metrics WHERE instability_decile = 1
UNION ALL
SELECT 'N Patients in Cohort' AS metric, CAST(COUNT(stay_id) AS FLOAT64) FROM all_metrics
UNION ALL
SELECT 'Avg proportion of time with hypotension (MAP<65) in Top Decile' AS metric, AVG(proportion_hypotensive) AS value FROM all_metrics WHERE instability_decile = 1
UNION ALL
SELECT 'Avg proportion of time with hypotension (MAP<65) in Cohort' AS metric, AVG(proportion_hypotensive) AS value FROM all_metrics
UNION ALL
SELECT 'Avg max tachycardia (bpm) in Top Decile' AS metric, AVG(max_tachycardia) AS value FROM all_metrics WHERE instability_decile = 1
UNION ALL
SELECT 'Avg max tachycardia (bpm) in Cohort' AS metric, AVG(max_tachycardia) AS value FROM all_metrics
UNION ALL
SELECT 'Avg ICU LOS (days) in Top Decile' AS metric, AVG(icu_los) AS value FROM all_metrics WHERE instability_decile = 1
UNION ALL
SELECT 'Avg ICU LOS (days) in Cohort' AS metric, AVG(icu_los) AS value FROM all_metrics
UNION ALL
SELECT 'Mortality rate in Top Decile' AS metric, AVG(CAST(hospital_expire_flag AS FLOAT64)) AS value FROM all_metrics WHERE instability_decile = 1
UNION ALL
SELECT 'Mortality rate in Cohort' AS metric, AVG(CAST(hospital_expire_flag AS FLOAT64)) AS value FROM all_metrics;