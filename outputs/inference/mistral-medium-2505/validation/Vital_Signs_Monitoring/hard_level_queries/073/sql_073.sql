WITH
-- Define ICH ICD codes
ich_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I61.%' OR icd_code LIKE 'I62.%'
),

-- Get female patients aged 47-57 with ICH
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN ich_codes ic ON d.icd_code = ic.icd_code
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths for LOS calculation
),

-- Get vital signs in first 72 hours of ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    di.category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  JOIN cohort co ON c.subject_id = co.subject_id AND c.hadm_id = co.hadm_id AND c.stay_id = co.stay_id
  WHERE
    c.charttime BETWEEN co.icu_intime AND TIMESTAMP_ADD(co.icu_intime, INTERVAL 72 HOUR)
    AND di.category IN ('Heart Rate', 'Blood Pressure', 'Respiratory Rate', 'Oxygen Saturation')
    AND c.valuenum IS NOT NULL
),

-- Calculate instability score (simplified example - adjust weights as needed)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Example scoring: sum of deviations from normal ranges
    SUM(
      CASE
        WHEN category = 'Heart Rate' THEN
          CASE
            WHEN valuenum < 60 THEN 60 - valuenum
            WHEN valuenum > 100 THEN valuenum - 100
            ELSE 0
          END
        WHEN category = 'Blood Pressure' THEN
          CASE
            WHEN valuenum < 90 THEN 90 - valuenum
            WHEN valuenum > 140 THEN valuenum - 140
            ELSE 0
          END
        WHEN category = 'Respiratory Rate' THEN
          CASE
            WHEN valuenum < 12 THEN 12 - valuenum
            WHEN valuenum > 20 THEN valuenum - 20
            ELSE 0
          END
        WHEN category = 'Oxygen Saturation' THEN
          CASE
            WHEN valuenum < 90 THEN 90 - valuenum
            ELSE 0
          END
        ELSE 0
      END
    ) AS instability_score
  FROM vital_signs
  GROUP BY subject_id, hadm_id, stay_id
),

-- Calculate percentiles
percentiles AS (
  SELECT
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM instability_scores
),

-- Get top decile patients
top_decile AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.instability_score,
    p.percentile,
    TIMESTAMP_DIFF(c.icu_outtime, c.icu_intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM instability_scores i
  JOIN cohort c ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id AND i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  JOIN percentiles p ON i.instability_score = p.instability_score
  WHERE p.percentile >= 0.9
)

-- Final results
SELECT
  -- Percentile for score of 75
  (SELECT PERCENT_RANK() OVER (ORDER BY instability_score) FROM instability_scores WHERE instability_score = 75) AS percentile_for_75,

  -- Average ICU LOS for top decile
  AVG(icu_los_hours) AS avg_icu_los_hours_top_decile,

  -- Mortality rate for top decile
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate_top_decile

FROM top_decile;