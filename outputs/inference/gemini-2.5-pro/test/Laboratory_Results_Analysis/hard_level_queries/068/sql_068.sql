WITH
-- Step 1: Define the base population of female patients aged 89-99
patients_aged AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 89 AND 99
),

-- Step 2: Identify hospital admissions with a septic shock diagnosis
septic_shock_hadms AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('78552', 'R6521') -- ICD-9: 785.52, ICD-10: R65.21
),

-- Step 3: Categorize patients into the 'Septic Shock' and 'General Inpatients' cohorts
cohorts AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    CASE
      WHEN s.hadm_id IS NOT NULL THEN 'Septic Shock'
      ELSE 'General Inpatients'
    END AS cohort_group
  FROM
    patients_aged AS pa
  LEFT JOIN
    septic_shock_hadms AS s
    ON pa.hadm_id = s.hadm_id
),

-- Analysis Part 1: Instability Score for the Septic Shock cohort
-- Get and normalize vital signs within the first 48 hours for the septic shock cohort
vitals_filtered AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    v.charttime,
    CASE
      WHEN v.itemid IN (223762, 223761) THEN 'Temp'
      WHEN v.itemid = 220045 THEN 'HR'
      WHEN v.itemid IN (220052, 220181, 225312) THEN 'MAP'
      WHEN v.itemid = 220210 THEN 'RR'
    END AS vital_label,
    CASE
      WHEN v.itemid = 223761 THEN (v.valuenum - 32) * 5 / 9 -- Convert Fahrenheit to Celsius
      ELSE v.valuenum
    END AS value
  FROM
    cohorts AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS v
    ON c.hadm_id = v.hadm_id
  WHERE
    c.cohort_group = 'Septic Shock'
    AND v.itemid IN (
      220045, -- Heart Rate
      220052, 220181, 225312, -- Mean Arterial Pressure (various)
      220210, -- Respiratory Rate
      223762, -- Temperature Celsius
      223761  -- Temperature Fahrenheit
    )
    AND v.valuenum IS NOT NULL
    AND DATETIME_DIFF(v.charttime, c.admittime, HOUR) BETWEEN 0 AND 48
),
-- Calculate the instability score (count of abnormal vitals) at each timepoint
instability_scores AS (
  SELECT
    (MAX(CASE WHEN vital_label = 'HR' AND (value < 60 OR value > 100) THEN 1 ELSE 0 END)) +
    (MAX(CASE WHEN vital_label = 'MAP' AND value < 65 THEN 1 ELSE 0 END)) +
    (MAX(CASE WHEN vital_label = 'RR' AND (value < 12 OR value > 20) THEN 1 ELSE 0 END)) +
    (MAX(CASE WHEN vital_label = 'Temp' AND (value < 36.0 OR value > 38.0) THEN 1 ELSE 0 END))
    AS instability_score
  FROM
    vitals_filtered
  GROUP BY
    subject_id, hadm_id, charttime
),
-- Compute quantiles for the instability score (efficiently)
instability_quantiles AS (
    SELECT
        APPROX_QUANTILES(instability_score, 4) AS quantiles
    FROM instability_scores
),
instability_results AS (
    SELECT 'Instability Score' AS metric_type, 'Q1' AS metric_name, CAST(q.quantiles[OFFSET(1)] AS STRING) AS septic_shock_value, CAST(NULL AS STRING) AS general_inpatients_value FROM instability_quantiles q
    UNION ALL
    SELECT 'Instability Score', 'Median', CAST(q.quantiles[OFFSET(2)] AS STRING), CAST(NULL AS STRING) FROM instability_quantiles q
    UNION ALL
    SELECT 'Instability Score', 'Q3', CAST(q.quantiles[OFFSET(3)] AS STRING), CAST(NULL AS STRING) FROM instability_quantiles q
    UNION ALL
    SELECT 'Instability Score', 'IQR', CAST(q.quantiles[OFFSET(3)] - q.quantiles[OFFSET(1)] AS STRING), CAST(NULL AS STRING) FROM instability_quantiles q
),

-- Analysis Part 2: Abnormal Lab Frequencies
lab_results AS (
  WITH all_labs AS (
    SELECT
      c.cohort_group,
      le.itemid,
      CASE
        WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1
        ELSE 0
      END AS is_abnormal
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
      cohorts AS c ON le.hadm_id = c.hadm_id
    WHERE
      le.itemid IN (
        51301, -- White Blood Cell Count
        51222, -- Hemoglobin
        51265, -- Platelet Count
        50882, -- Bicarbonate
        50912, -- Creatinine
        50813, -- Lactate
        50971, -- Potassium
        50983  -- Sodium
      )
      AND le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
  )
  SELECT
    'Abnormal Lab Freq' AS metric_type,
    d.label AS metric_name,
    SAFE_DIVIDE(
      SUM(CASE WHEN l.cohort_group = 'Septic Shock' THEN l.is_abnormal ELSE 0 END),
      NULLIF(SUM(CASE WHEN l.cohort_group = 'Septic Shock' THEN 1 ELSE 0 END), 0)
    ) AS septic_shock_value,
    SAFE_DIVIDE(
      SUM(CASE WHEN l.cohort_group = 'General Inpatients' THEN l.is_abnormal ELSE 0 END),
      NULLIF(SUM(CASE WHEN l.cohort_group = 'General Inpatients' THEN 1 ELSE 0 END), 0)
    ) AS general_inpatients_value
  FROM
    all_labs AS l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  GROUP BY
    d.label
),

-- Analysis Part 3: Cohort LOS and Mortality
summary_results AS (
  WITH cohort_stats AS (
    SELECT
      cohort_group,
      AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
      AVG(hospital_expire_flag) AS mortality_rate
    FROM
      cohorts
    GROUP BY
      cohort_group
  )
  SELECT
    'Cohort Metric' AS metric_type,
    'Avg LOS (days)' AS metric_name,
    MAX(CASE WHEN cohort_group = 'Septic Shock' THEN avg_los_days END) AS septic_shock_value,
    MAX(CASE WHEN cohort_group = 'General Inpatients' THEN avg_los_days END) AS general_inpatients_value
  FROM cohort_stats
  UNION ALL
  SELECT
    'Cohort Metric' AS metric_type,
    'Mortality Rate' AS metric_name,
    MAX(CASE WHEN cohort_group = 'Septic Shock' THEN mortality_rate END) AS septic_shock_value,
    MAX(CASE WHEN cohort_group = 'General Inpatients' THEN mortality_rate END) AS general_inpatients_value
  FROM cohort_stats
)

-- Final Step: Combine all results into a single report
SELECT
  metric_type,
  metric_name,
  septic_shock_value,
  general_inpatients_value
FROM
  instability_results

UNION ALL

SELECT
  metric_type,
  metric_name,
  CAST(ROUND(septic_shock_value, 4) AS STRING) AS septic_shock_value,
  CAST(ROUND(general_inpatients_value, 4) AS STRING) AS general_inpatients_value
FROM
  lab_results

UNION ALL

SELECT
  metric_type,
  metric_name,
  CAST(ROUND(septic_shock_value, 4) AS STRING) AS septic_shock_value,
  CAST(ROUND(general_inpatients_value, 4) AS STRING) AS general_inpatients_value
FROM
  summary_results
ORDER BY
  metric_type, metric_name;