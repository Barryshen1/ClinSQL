WITH cohort AS (
  -- 1. Identify female patients age 75–85 with mechanical ventilation in first 48h
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.subject_id = ic.subject_id
        AND pe.hadm_id = ic.hadm_id
        AND pe.stay_id = ic.stay_id
        -- placeholder itemids for invasive ventilation; replace with actual codes
        AND pe.itemid IN (225719, 301529, 300424)
        AND pe.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
    )
),

vitals AS (
  -- 2. Extract hypotension and tachycardia counts in first 48h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    -- hypotension: MAP < 65
    SUM(CASE
          WHEN ce.itemid IN (
            SELECT itemid
            FROM `physionet-data.mimiciv_3_1_icu.d_items`
            WHERE LOWER(label) LIKE '%mean arterial pressure%'
               OR LOWER(abbreviation) = 'map'
          )
          AND ce.valuenum < 65 THEN 1
          ELSE 0
        END) AS hypotension_count,
    -- tachycardia: HR > 100
    SUM(CASE
          WHEN ce.itemid IN (
            SELECT itemid
            FROM `physionet-data.mimiciv_3_1_icu.d_items`
            WHERE LOWER(label) LIKE '%heart rate%'
               OR LOWER(abbreviation) = 'hr'
          )
          AND ce.valuenum > 100 THEN 1
          ELSE 0
        END) AS tachycardia_count
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = c.subject_id
      AND ce.hadm_id = c.hadm_id
      AND ce.stay_id = c.stay_id
      AND ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los
),

scores AS (
  -- 3. Compute composite score
  SELECT
    v.*,
    (v.hypotension_count + v.tachycardia_count) AS composite_score
  FROM vitals v
),

percentiles AS (
  -- 4. Compute percentiles of composite score
  SELECT
    APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS p75
  FROM scores
),

top_quartile AS (
  -- 5. Select stays in the top 25% of composite score, bring in mortality
  SELECT
    s.*,
    adm.hospital_expire_flag
  FROM
    scores s
    CROSS JOIN percentiles pct
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON s.subject_id = adm.subject_id
      AND s.hadm_id = adm.hadm_id
  WHERE
    s.composite_score >= pct.p75
)

-- 6. Final output: 90th percentile and summary statistics for top quartile
SELECT
  (SELECT p90 FROM percentiles) AS composite_score_90th_percentile,
  COUNT(*) AS top_quartile_n,
  AVG(hypotension_count) AS avg_hypotension_count,
  AVG(tachycardia_count) AS avg_tachycardia_count,
  AVG(los) AS avg_icu_los_hours,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
FROM
  top_quartile;