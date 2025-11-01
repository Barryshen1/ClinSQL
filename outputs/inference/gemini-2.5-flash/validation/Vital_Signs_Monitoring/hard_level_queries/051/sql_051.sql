WITH icu_cohort AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    ie.intime,
    ie.outtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ie
    ON adm.hadm_id = ie.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
),
-- Identify admissions associated with Ischemic Stroke
stroke_admissions AS (
  SELECT DISTINCT
    cohort.subject_id,
    cohort.hadm_id,
    cohort.stay_id,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE
          di.subject_id = cohort.subject_id
          AND di.hadm_id = cohort.hadm_id
          AND (
            (di.icd_version = 9 AND di.icd_code LIKE '434%') -- ICD-9 for Ischemic Stroke
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I63%') -- ICD-10 for Ischemic Stroke
          )
      ) THEN TRUE
      ELSE FALSE
    END AS is_ischemic_stroke
  FROM
    icu_cohort AS cohort
),
-- Gather vital signs within the first 48 hours of ICU stay
vital_signs_48hr AS (
  SELECT
    ie.stay_id,
    ce.itemid,
    ce.valuenum,
    ie.intime
  FROM
    icu_cohort AS ie
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ie.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (
      220045, -- Heart Rate
      220050, -- Arterial Blood Pressure SBP
      220210, -- Respiratory Rate
      223761  -- Temperature F
    )
),
-- Calculate the "48-hour instability score" for each stay
-- Score is defined as the count of abnormal vital sign readings
instability_score_calc AS (
  SELECT
    vs.stay_id,
    SUM(
      CASE
        WHEN vs.itemid = 220045 AND (vs.valuenum < 60 OR vs.valuenum > 100) THEN 1 -- HR (normal: 60-100 bpm)
        WHEN vs.itemid = 220050 AND (vs.valuenum < 90 OR vs.valuenum > 140) THEN 1 -- SBP (normal: 90-140 mmHg)
        WHEN vs.itemid = 220210 AND (vs.valuenum < 12 OR vs.valuenum > 20) THEN 1 -- RR (normal: 12-20 bpm)
        WHEN vs.itemid = 223761 AND (vs.valuenum < 96.8 OR vs.valuenum > 99.5) THEN 1 -- Temp F (normal: 96.8-99.5 F)
        ELSE 0
      END
    ) AS instability_score
  FROM
    vital_signs_48hr AS vs
  GROUP BY
    vs.stay_id
),
-- Combine all necessary data into a final cohort table
final_cohort_data AS (
  SELECT
    icc.subject_id,
    icc.hadm_id,
    icc.stay_id,
    icc.intime,
    icc.outtime,
    icc.hospital_expire_flag,
    COALESCE(str.is_ischemic_stroke, FALSE) AS is_ischemic_stroke, -- Default to FALSE if no stroke diagnosis found
    COALESCE(isc.instability_score, 0) AS instability_score, -- Default to 0 if no vital sign data or no abnormalities
    -- Calculate ICU LOS in hours
    TIMESTAMP_DIFF(icc.outtime, icc.intime, HOUR) AS icu_los_hours
  FROM
    icu_cohort AS icc
  LEFT JOIN
    stroke_admissions AS str
    ON icc.stay_id = str.stay_id
  LEFT JOIN
    instability_score_calc AS isc
    ON icc.stay_id = isc.stay_id
),
-- Calculate the 95th-percentile instability score for ischemic stroke patients
p95_ischemic_stroke_score AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER () AS p95_score
  FROM
    final_cohort_data
  WHERE
    is_ischemic_stroke = TRUE
  LIMIT 1
),
-- Calculate the threshold for the top instability quartile across the entire cohort
top_quartile_threshold AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.75) OVER () AS quartile_score_threshold
  FROM
    final_cohort_data
  LIMIT 1
),
-- Filter for patients in the top instability quartile
top_quartile_patients AS (
  SELECT
    fcd.*
  FROM
    final_cohort_data AS fcd,
    top_quartile_threshold AS tqt
  WHERE
    fcd.instability_score >= tqt.quartile_score_threshold
)
-- Display the 95th-percentile instability score for ischemic stroke
SELECT
  '95th-percentile 48-hour instability score for (Ischemic Stroke)' AS metric_description,
  CAST(p95s.p95_score AS STRING) AS value_or_comparison_group,
  NULL AS N,
  NULL AS mean_instability,
  NULL AS mean_abnormal_episodes,
  NULL AS mean_icu_los_hrs,
  NULL AS hospital_mortality_rate
FROM
  p95_ischemic_stroke_score AS p95s

UNION ALL

-- Compare characteristics for the top instability quartile (Ischemic Stroke vs. General ICU (Non-Stroke))
SELECT
  'Comparison for Top Instability Quartile' AS metric_description,
  CASE
    WHEN tqp.is_ischemic_stroke THEN 'Ischemic Stroke'
    ELSE 'General ICU (Non-Stroke)'
  END AS value_or_comparison_group,
  COUNT(DISTINCT tqp.stay_id) AS N,
  AVG(tqp.instability_score) AS mean_instability,
  AVG(tqp.instability_score) AS mean_abnormal_episodes, -- "mean abnormal episodes" is equivalent to "mean instability" by our definition
  AVG(tqp.icu_los_hours) AS mean_icu_los_hrs,
  AVG(tqp.hospital_expire_flag) AS hospital_mortality_rate
FROM
  top_quartile_patients AS tqp
GROUP BY
  value_or_comparison_group
ORDER BY
  metric_description DESC, value_or_comparison_group;