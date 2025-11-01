WITH
-- Get male patients aged 81-91
male_patients_81_91 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients_81_91 p ON s.subject_id = p.subject_id
),

-- Get systolic BP measurements in first 48 hours of each ICU stay
systolic_bp AS (
  SELECT
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.stay_id = s.stay_id
  WHERE
    c.itemid = 220050  -- Systolic BP
    AND c.valuenum > 0  -- Valid numeric value
    AND c.valuenum BETWEEN 50 AND 300  -- Reasonable range
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),

-- Calculate average systolic BP per stay
avg_bp_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_systolic_bp
  FROM
    systolic_bp
  GROUP BY
    stay_id
  HAVING
    COUNT(valuenum) > 0  -- Ensure at least one measurement
)

-- Calculate percentile for 150 mmHg
SELECT
  PERCENT_RANK() OVER (ORDER BY avg_systolic_bp) AS percentile
FROM
  avg_bp_per_stay
WHERE
  avg_systolic_bp = 150  -- This will return the percentile for 150 mmHg;