WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 51 AND 61
),

-- Identify patients on invasive mechanical ventilation in first 48h
vent AS (
  SELECT DISTINCT
    ce.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  WHERE
    di.label IN (
      'Invasive Ventilation',
      'Mechanical Ventilation',
      'Ventilation'
    )
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
),

-- Compute instability score components in first 48h
scores AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    MIN(ce.valuenum) AS gcs_min,
    MAX(CASE WHEN di.label = 'Arterial Pressure Mean' THEN ce.valuenum END) AS map_max,
    MAX(CASE WHEN di.label = 'Bilirubin' THEN ce.valuenum END) AS bilirubin_max,
    MIN(CASE WHEN di.label = 'Platelets' THEN ce.valuenum END) AS platelets_min,
    MAX(CASE WHEN di.label = 'Creatinine' THEN ce.valuenum END) AS creatinine_max,
    MIN(CASE WHEN di.label IN ('PaO2', 'PO2') THEN ce.valuenum END) AS pao2_min
  FROM
    cohort c
  JOIN
    vent v ON c.stay_id = v.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id, c.los, c.hospital_expire_flag
),

-- Compute instability score (simple additive proxy)
instability_scores AS (
  SELECT
    stay_id,
    los,
    hospital_expire_flag,
    COALESCE(gcs_min, 15) +
    COALESCE(map_max, 0) +
    COALESCE(bilirubin_max, 0) +
    (150 - COALESCE(platelets_min, 150)) +
    COALESCE(creatinine_max, 0) +
    (500 - COALESCE(pao2_min, 500)) AS instability_score
  FROM
    scores
),

-- Add percentiles
score_percentiles AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) * 100 AS percentile_rank
  FROM
    instability_scores
),

-- Find percentile of score = 80
percentile_of_80 AS (
  SELECT
    MAX(CASE WHEN instability_score <= 80 THEN percentile_rank END) AS percentile_of_80
  FROM
    score_percentiles
),

-- Top decile (most unstable)
top_decile AS (
  SELECT
    *
  FROM
    score_percentiles
  WHERE
    percentile_rank >= 90
)

-- Final output
SELECT
  (SELECT percentile_of_80 FROM percentile_of_80) AS percentile_of_score_80,
  AVG(los) AS avg_icu_los_top_decile,
  AVG(hospital_expire_flag) AS mortality_rate_top_decile
FROM
  top_decile;