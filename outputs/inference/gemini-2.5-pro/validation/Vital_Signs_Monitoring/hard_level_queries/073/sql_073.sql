WITH
ich_admissions AS (
  -- Step 1: Identify all hospital admissions with an ICH diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Subarachnoid, Intracerebral, and Other Intracranial Hemorrhage
    (icd_version = 9 AND (
      SUBSTR(icd_code, 1, 3) IN ('430', '431', '432')
    )) OR
    -- ICD-10 codes for Subarachnoid, Intracerebral, and Other Nontraumatic Intracranial Hemorrhage
    (icd_version = 10 AND (
      SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62')
    ))
),
cohort AS (
  -- Step 2: Filter for female ICU patients aged 47-57 with ICH
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN ich_admissions AS ich ON icu.hadm_id = ich.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON icu.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm ON icu.hadm_id = adm.hadm_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 47 AND 57
),
instability_scores AS (
  -- Step 3: Calculate the vital-sign instability score for each patient in the cohort
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COALESCE(SUM(
        CASE
            -- Heart Rate (bpm): normal 60-100
            WHEN ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
            -- Systolic Blood Pressure (mmHg): normal 90-140
            WHEN ce.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 140) THEN 1
            -- Diastolic Blood Pressure (mmHg): normal 60-90
            WHEN ce.itemid = 220180 AND (ce.valuenum < 60 OR ce.valuenum > 90) THEN 1
            -- Respiratory Rate (breaths/min): normal 12-20
            WHEN ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1
            -- Temperature Celsius (°C): normal 36.5-37.5
            WHEN ce.itemid = 223762 AND (ce.valuenum < 36.5 OR ce.valuenum > 37.5) THEN 1
            -- SpO2 (%): normal >= 94
            WHEN ce.itemid = 220277 AND ce.valuenum < 94 THEN 1
            ELSE 0
        END
    ), 0) AS instability_score
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (
        220045, -- Heart Rate
        220179, -- Non Invasive Blood Pressure systolic
        220180, -- Non Invasive Blood Pressure diastolic
        220210, -- Respiratory Rate
        223762, -- Temperature Celsius
        220277  -- O2 saturation pulseoxymetry
    )
  GROUP BY
    c.stay_id,
    c.los,
    c.hospital_expire_flag
),
percentile_calculation AS (
  -- Step 4a: Calculate what percentile a score of 75 represents
  SELECT
    100 * AVG(CASE WHEN instability_score <= 75 THEN 1.0 ELSE 0.0 END) AS percentile_of_score_75
  FROM instability_scores
),
top_decile_metrics AS (
  -- Step 4b: Calculate average LOS and mortality for the top decile of scores
  SELECT
    AVG(los) AS avg_los_top_decile,
    100 * AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_decile_percent
  FROM (
    SELECT
      los,
      hospital_expire_flag,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS score_decile
    FROM instability_scores
  ) AS ranked_scores
  WHERE score_decile = 1
)
-- Final Step: Combine and present the results
SELECT
  pct.percentile_of_score_75,
  tdm.avg_los_top_decile,
  tdm.mortality_rate_top_decile_percent
FROM percentile_calculation AS pct, top_decile_metrics AS tdm;