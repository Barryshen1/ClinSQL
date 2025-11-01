WITH
-- Get male ICU patients aged 88-98
patient_icu AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 88 AND 98
),

-- Calculate instability score (simplified example - would need clinical validation)
instability_scores AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    -- Example instability score calculation (would need proper clinical definition)
    -- This is a placeholder - actual calculation would use multiple parameters
    AVG(CASE
        WHEN ce.itemid IN (220045, 220050) THEN ce.valuenum -- Heart rate
        ELSE NULL
      END) AS heart_rate,
    AVG(CASE
        WHEN ce.itemid IN (220050, 220179) THEN ce.valuenum -- Systolic BP
        ELSE NULL
      END) AS systolic_bp,
    AVG(CASE
        WHEN ce.itemid IN (220210, 220277) THEN ce.valuenum -- Oxygen saturation
        ELSE NULL
      END) AS spo2,
    -- Simplified instability score (example only)
    -- In reality, this would be a more complex clinical calculation
    (AVG(CASE
        WHEN ce.itemid IN (220045, 220050) THEN ce.valuenum
        ELSE NULL
      END) / NULLIF(AVG(CASE
        WHEN ce.itemid IN (220050, 220179) THEN ce.valuenum
        ELSE NULL
      END), 0) * 100) AS instability_score
  FROM
    patient_icu p
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON p.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220050, 220179, 220210, 220277) -- Example itemids
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id
),

-- Calculate percentiles
percentile_ranks AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM
    instability_scores
),

-- Get the percentile for score of 85
score_percentile AS (
  SELECT
    percentile
  FROM
    percentile_ranks
  WHERE
    instability_score = 85
),

-- Identify most unstable quartile (top 25%)
most_unstable AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    s.instability_score,
    p.icu_los,
    p.hospital_expire_flag
  FROM
    percentile_ranks s
  JOIN
    patient_icu p ON s.subject_id = p.subject_id AND s.hadm_id = p.hadm_id AND s.stay_id = p.stay_id
  WHERE
    s.percentile >= 0.75
)

-- Final results
SELECT
  (SELECT percentile FROM score_percentile) AS percentile_for_score_85,
  AVG(icu_los) AS avg_icu_los_most_unstable,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(*) AS hospital_mortality_rate_most_unstable
FROM
  most_unstable;