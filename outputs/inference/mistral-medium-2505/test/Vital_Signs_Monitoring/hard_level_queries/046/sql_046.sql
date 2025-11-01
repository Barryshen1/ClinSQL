WITH
-- Get male patients aged 84-94
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),

-- Get ischemic stroke admissions
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I63.%'
    AND a.subject_id IN (SELECT subject_id FROM male_patients)
),

-- First get all ICU stays with row numbers
icu_stays_with_seq AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    s.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS icu_stay_seq
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    stroke_admissions a
  ON
    s.subject_id = a.subject_id
    AND s.hadm_id = a.hadm_id
),

-- Then filter for first ICU stay
first_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime,
    icu_los
  FROM
    icu_stays_with_seq
  WHERE
    icu_stay_seq = 1
),

-- Get vital sign measurements in first 72 hours
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    d.label AS item_label,
    d.category AS item_category
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
  ON
    c.itemid = d.itemid
  JOIN
    first_icu_stays s
  ON
    c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  WHERE
    c.charttime BETWEEN s.icu_intime AND DATETIME_ADD(s.icu_intime, INTERVAL 72 HOUR)
    AND d.category IN ('Vital Signs', 'Heart Rate', 'Blood Pressure', 'Respiratory Rate')
),

-- Calculate instability score for each patient (simplified example)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Example instability score calculation (would need clinical validation)
    -- This is a simplified placeholder - actual calculation would be more complex
    SUM(
      CASE
        WHEN item_label LIKE '%Heart Rate%' AND (valuenum < 50 OR valuenum > 100) THEN 1
        WHEN item_label LIKE '%Systolic%' AND (valuenum < 90 OR valuenum > 180) THEN 1
        WHEN item_label LIKE '%Diastolic%' AND (valuenum < 60 OR valuenum > 110) THEN 1
        WHEN item_label LIKE '%Respiratory Rate%' AND (valuenum < 12 OR valuenum > 25) THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate percentiles
percentiles AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM
    instability_scores
),

-- Get top quartile patients
top_quartile AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.instability_score,
    s.icu_los,
    a.hospital_expire_flag
  FROM
    instability_scores i
  JOIN
    first_icu_stays s
  ON
    i.subject_id = s.subject_id
    AND i.hadm_id = s.hadm_id
    AND i.stay_id = s.stay_id
  JOIN
    stroke_admissions a
  ON
    i.subject_id = a.subject_id
    AND i.hadm_id = a.hadm_id
  WHERE
    i.instability_score >= (
      SELECT
        MAX(instability_score)
      FROM
        percentiles
      WHERE
        percentile <= 0.75
    )
)

-- Final results
SELECT
  -- Percentile for score of 80
  (SELECT percentile FROM percentiles WHERE instability_score = 80) AS percentile_for_score_80,

  -- ICU LOS and mortality for top quartile
  AVG(icu_los) AS avg_icu_los_top_quartile,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) /
    COUNT(*) AS mortality_rate_top_quartile
FROM
  top_quartile;