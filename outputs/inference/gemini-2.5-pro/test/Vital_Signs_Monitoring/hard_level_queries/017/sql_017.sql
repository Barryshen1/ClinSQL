WITH
-- Step 1: Identify all ICU stays that have a diagnosis of asthma
asthma_stays AS (
  SELECT DISTINCT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON icu.hadm_id = dx.hadm_id
  WHERE
    -- ICD-9 codes for asthma start with '493'
    -- ICD-10 codes for asthma start with 'J45'
    dx.icd_code LIKE '493%' OR dx.icd_code LIKE 'J45%'
),

-- Step 2: Define the base population: female ICU patients aged 83-93
-- and label them as 'Asthma' or 'Control'
cohorts AS (
  SELECT
    i.stay_id,
    i.intime,
    a.hospital_expire_flag,
    -- Calculate ICU length of stay in fractional days for more precision
    DATETIME_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS icu_los_days,
    CASE
      WHEN ast.stay_id IS NOT NULL THEN 'Asthma'
      ELSE 'Control'
    END AS cohort_group
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN
    asthma_stays AS ast
    ON i.stay_id = ast.stay_id
  WHERE
    p.gender = 'F'
    -- Calculate age at ICU admission
    AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 83 AND 93
),

-- Step 3: Define an "Instability Score" based on abnormal vital signs
-- during the first 72 hours of the ICU stay. Each abnormal event contributes 1 point.
instability_events AS (
  SELECT
    c.stay_id,
    -- Define points for each unstable vital sign measurement
    CASE
      -- Heart Rate (itemid: 220045), abnormal if < 50 or > 110 bpm
      WHEN ce.itemid = 220045 AND (ce.valuenum < 50 OR ce.valuenum > 110) THEN 1
      -- Mean Arterial Pressure (itemid: 220052), abnormal if < 65 mmHg
      WHEN ce.itemid = 220052 AND ce.valuenum < 65 THEN 1
      -- Respiratory Rate (itemid: 220210), abnormal if < 10 or > 22 breaths/min
      WHEN ce.itemid = 220210 AND (ce.valuenum < 10 OR ce.valuenum > 22) THEN 1
      -- SpO2 (itemid: 220277), abnormal if < 90%
      WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1
      -- Temperature Fahrenheit (itemid: 223761), abnormal if < 96.8 or > 100.4 F
      WHEN ce.itemid = 223761 AND (ce.valuenum < 96.8 OR ce.valuenum > 100.4) THEN 1
      -- GCS Total (itemid: 220739), abnormal if < 15
      WHEN ce.itemid = 220739 AND ce.valuenum < 15 THEN 1
      ELSE 0
    END AS instability_point
  FROM
    cohorts AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  WHERE
    -- Filter for events within the first 72 hours of ICU admission
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    -- Filter for the specific vital signs we are scoring
    AND ce.itemid IN (
      220045, -- Heart Rate
      220052, -- Mean Arterial Pressure (Invasive)
      220210, -- Respiratory Rate
      220277, -- O2 saturation pulseoxymetry
      223761, -- Temperature Fahrenheit
      220739  -- GCS Total
    )
    AND ce.valuenum IS NOT NULL
),

-- Step 4: Calculate the total instability score for each patient by summing points
patient_scores AS (
  SELECT
    stay_id,
    SUM(instability_point) AS total_instability_score
  FROM
    instability_events
  GROUP BY
    stay_id
),

-- Step 5: Combine cohort data with calculated scores, LOS, and mortality
final_data AS (
  SELECT
    c.cohort_group,
    c.icu_los_days,
    c.hospital_expire_flag,
    -- If a patient had no vital signs recorded, their score is 0
    COALESCE(ps.total_instability_score, 0) AS instability_score
  FROM
    cohorts AS c
  LEFT JOIN
    patient_scores AS ps
    ON c.stay_id = ps.stay_id
)

-- Step 6: Calculate and present the final comparative statistics for each cohort
SELECT
  cohort_group,
  COUNT(*) AS number_of_patients,
  -- "Score Burden" defined as the average instability score
  AVG(instability_score) AS score_burden,
  -- Standard deviation and percentiles of the instability score
  STDDEV(instability_score) AS score_stddev,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS score_p25,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS score_p50,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS score_p75,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS score_p95,
  -- Average ICU Length of Stay
  AVG(icu_los_days) AS avg_icu_los_days,
  -- Hospital mortality rate
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  final_data
GROUP BY
  cohort_group
ORDER BY
  cohort_group DESC;