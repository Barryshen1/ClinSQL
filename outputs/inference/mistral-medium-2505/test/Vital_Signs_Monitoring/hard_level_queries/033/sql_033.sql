WITH
-- Get female patients aged 51-61
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Calculate instability score components (simplified example)
instability_scores AS (
  SELECT
    i.subject_id,
    i.stay_id,
    -- Heart rate (example itemid for heart rate)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS max_heart_rate,
    -- Systolic blood pressure
    MIN(CASE WHEN ce.itemid = 220050 THEN ce.valuenum ELSE NULL END) AS min_sbp,
    -- Oxygen saturation
    MIN(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS min_spo2,
    -- Temperature
    MAX(CASE WHEN ce.itemid = 223761 THEN ce.valuenum ELSE NULL END) AS max_temp,
    -- Lactate (from labevents)
    MAX(CASE WHEN le.itemid = 50813 THEN le.valuenum ELSE NULL END) AS max_lactate
  FROM
    icu_stays i
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id
    AND i.stay_id = ce.stay_id
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON i.subject_id = le.subject_id
    AND i.hadm_id = le.hadm_id
    AND le.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY
    i.subject_id, i.stay_id
),

-- Calculate composite instability score (simplified example)
scored_patients AS (
  SELECT
    subject_id,
    stay_id,
    -- Example scoring formula (would need clinical validation)
    (COALESCE(max_heart_rate, 0) * 0.2 +
     (100 - COALESCE(min_sbp, 100)) * 0.3 +
     (100 - COALESCE(min_spo2, 100)) * 0.2 +
     (COALESCE(max_temp, 37) - 37) * 0.1 +
     COALESCE(max_lactate, 1) * 0.2) AS instability_score
  FROM
    instability_scores
),

-- Get mortality information
mortality_data AS (
  SELECT
    s.subject_id,
    s.stay_id,
    a.hospital_expire_flag
  FROM
    icu_stays s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id
    AND s.hadm_id = a.hadm_id
),

-- Combine all data
final_data AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.instability_score,
    i.icu_los_hours,
    m.hospital_expire_flag
  FROM
    scored_patients s
  JOIN
    icu_stays i ON s.subject_id = i.subject_id AND s.stay_id = i.stay_id
  JOIN
    mortality_data m ON s.subject_id = m.subject_id AND s.stay_id = m.stay_id
  WHERE
    s.instability_score IS NOT NULL
),

-- Calculate percentile ranks and deciles
ranked_data AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM
    final_data
),

-- Calculate percentile for score of 80
percentile_for_80 AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(CASE WHEN instability_score <= 80 THEN 1 ELSE 0 END) AS patients_below_80,
    SUM(CASE WHEN instability_score <= 80 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_for_80
  FROM
    final_data
),

-- Calculate metrics for most unstable decile
most_unstable_decile AS (
  SELECT
    AVG(icu_los_hours) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate,
    COUNT(*) AS patient_count
  FROM
    ranked_data
  WHERE
    decile = 1
)

-- Final results
SELECT
  -- Percentile for score of 80
  (SELECT percentile_for_80 FROM percentile_for_80) AS percentile_for_score_80,

  -- Metrics for most unstable decile
  (SELECT avg_icu_los FROM most_unstable_decile) AS avg_icu_los_most_unstable,
  (SELECT mortality_rate FROM most_unstable_decile) AS mortality_rate_most_unstable,
  (SELECT patient_count FROM most_unstable_decile) AS patient_count_most_unstable;