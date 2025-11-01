WITH map_hr_items AS (
  SELECT
    itemid,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial pressure%' OR abbreviation = 'MAP' THEN 'MAP'
      WHEN LOWER(label) LIKE '%heart rate%' OR abbreviation = 'HR' THEN 'HR'
      ELSE NULL
    END AS vital
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE
    (LOWER(label) LIKE '%mean arterial pressure%' OR abbreviation = 'MAP')
    OR (LOWER(label) LIKE '%heart rate%' OR abbreviation = 'HR')
),
-- Step 2: Get ICU stays for target cohort (male, age 82-92, acute resp failure)
target_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.subject_id = dx.subject_id AND icu.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND (
      -- ICD-10 codes
      (dx.icd_version = 10 AND (
        dx.icd_code LIKE 'J960%' OR
        dx.icd_code LIKE 'J962%' OR
        dx.icd_code LIKE 'J969%'
      ))
      -- ICD-9 codes
      OR (dx.icd_version = 9 AND (
        dx.icd_code IN ('51881', '51882', '51884')
      ))
    )
),
-- Step 3: Get all ICU stays (general ICU)
general_icustays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
),
-- Step 4: Get MAP and HR measurements in first 72h for both cohorts
vitals AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    mi.vital,
    ce.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN map_hr_items mi
    ON ce.itemid = mi.itemid
  -- Only keep measurements with non-null numeric value
  WHERE ce.valuenum IS NOT NULL
),
-- Step 5: Calculate instability burdens per stay for target cohort
target_burden AS (
  SELECT
    t.stay_id,
    t.subject_id,
    t.hadm_id,
    COUNTIF(v.vital = 'MAP') AS n_map,
    COUNTIF(v.vital = 'MAP' AND v.valuenum < 65) AS map_low,
    COUNTIF(v.vital = 'HR') AS n_hr,
    COUNTIF(v.vital = 'HR' AND v.valuenum > 100) AS hr_high,
    -- Composite instability score: sum of burdens
    SAFE_DIVIDE(COUNTIF(v.vital = 'MAP' AND v.valuenum < 65), COUNTIF(v.vital = 'MAP')) +
    SAFE_DIVIDE(COUNTIF(v.vital = 'HR' AND v.valuenum > 100), COUNTIF(v.vital = 'HR')) AS composite_score,
    SAFE_DIVIDE(COUNTIF(v.vital = 'MAP' AND v.valuenum < 65), COUNTIF(v.vital = 'MAP')) AS map_burden,
    SAFE_DIVIDE(COUNTIF(v.vital = 'HR' AND v.valuenum > 100), COUNTIF(v.vital = 'HR')) AS hr_burden
  FROM target_icustays t
  LEFT JOIN vitals v
    ON t.stay_id = v.stay_id
    AND v.charttime >= t.intime
    AND v.charttime < DATETIME_ADD(t.intime, INTERVAL 72 HOUR)
  GROUP BY t.stay_id, t.subject_id, t.hadm_id
),
-- Step 6: Calculate instability burdens per stay for general ICU
general_burden AS (
  SELECT
    g.stay_id,
    g.subject_id,
    g.hadm_id,
    COUNTIF(v.vital = 'MAP') AS n_map,
    COUNTIF(v.vital = 'MAP' AND v.valuenum < 65) AS map_low,
    COUNTIF(v.vital = 'HR') AS n_hr,
    COUNTIF(v.vital = 'HR' AND v.valuenum > 100) AS hr_high,
    SAFE_DIVIDE(COUNTIF(v.vital = 'MAP' AND v.valuenum < 65), COUNTIF(v.vital = 'MAP')) +
    SAFE_DIVIDE(COUNTIF(v.vital = 'HR' AND v.valuenum > 100), COUNTIF(v.vital = 'HR')) AS composite_score,
    SAFE_DIVIDE(COUNTIF(v.vital = 'MAP' AND v.valuenum < 65), COUNTIF(v.vital = 'MAP')) AS map_burden,
    SAFE_DIVIDE(COUNTIF(v.vital = 'HR' AND v.valuenum > 100), COUNTIF(v.vital = 'HR')) AS hr_burden
  FROM general_icustays g
  LEFT JOIN vitals v
    ON g.stay_id = v.stay_id
    AND v.charttime >= g.intime
    AND v.charttime < DATETIME_ADD(g.intime, INTERVAL 72 HOUR)
  GROUP BY g.stay_id, g.subject_id, g.hadm_id
),
-- Step 7: Add LOS and mortality for target cohort
target_final AS (
  SELECT
    tb.*,
    ti.los,
    a.hospital_expire_flag
  FROM target_burden tb
  INNER JOIN target_icustays ti
    ON tb.stay_id = ti.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON tb.hadm_id = a.hadm_id
),
-- Step 8: Add LOS and mortality for general ICU
general_final AS (
  SELECT
    gb.*,
    gi.los,
    a.hospital_expire_flag
  FROM general_burden gb
  INNER JOIN general_icustays gi
    ON gb.stay_id = gi.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON gb.hadm_id = a.hadm_id
),
-- Step 9: Aggregate statistics for target cohort
target_stats AS (
  SELECT
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS p25_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(2)] AS median_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] - APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS iqr_composite_score,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(composite_score) AS avg_composite_score,
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM target_final
  WHERE n_map > 0 AND n_hr > 0 -- exclude stays with no MAP or HR measurements
),
-- Step 10: Aggregate statistics for general ICU
general_stats AS (
  SELECT
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS p25_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(2)] AS median_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75_composite_score,
    APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] - APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS iqr_composite_score,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(composite_score) AS avg_composite_score,
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM general_final
  WHERE n_map > 0 AND n_hr > 0
)
-- Final output: compare target and general ICU
SELECT
  'Target cohort: Male ICU patients 82-92 with acute respiratory failure' AS cohort,
  *
FROM target_stats
UNION ALL
SELECT
  'General ICU population' AS cohort,
  *
FROM general_stats;