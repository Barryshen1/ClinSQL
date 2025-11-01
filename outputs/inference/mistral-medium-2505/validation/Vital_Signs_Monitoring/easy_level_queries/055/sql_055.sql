WITH
-- Get male patients aged 76-86
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get ICU stays in step-down/IMC units
stepdown_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    eligible_patients p ON s.subject_id = p.subject_id
  WHERE
    s.first_careunit IN ('Stepdown', 'IMC')
    OR s.last_careunit IN ('Stepdown', 'IMC')
),

-- Get SBP measurements in first 24 hours of ICU stay
sbp_measurements AS (
  SELECT
    c.valuenum AS sbp_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    stepdown_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220050  -- NBP Systolic (verify in d_items)
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.valuenum BETWEEN 50 AND 250  -- Plausible SBP range
)

-- Calculate standard deviation of SBP
SELECT
  STDDEV(sbp_value) AS sbp_sd
FROM
  sbp_measurements;