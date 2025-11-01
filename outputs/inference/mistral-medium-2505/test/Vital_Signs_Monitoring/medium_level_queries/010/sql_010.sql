WITH
-- Get the itemid for systolic BP
systolic_bp_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Systolic Blood Pressure'
  LIMIT 1
),

-- Filter female patients aged 77-87
female_patients_77_87 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get ICU stays for these patients
icu_stays_filtered AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN female_patients_77_87 p ON s.subject_id = p.subject_id
),

-- Calculate average systolic BP per stay in first 48 hours
avg_sbp_per_stay AS (
  SELECT
    s.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM icu_stays_filtered s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON s.stay_id = ce.stay_id
  JOIN systolic_bp_item sbp ON ce.itemid = sbp.itemid
  WHERE ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
  HAVING COUNT(ce.valuenum) > 0  -- Ensure at least one reading
),

-- Calculate percentiles
percentiles AS (
  SELECT
    avg_sbp,
    PERCENT_RANK() OVER (ORDER BY avg_sbp) AS percentile
  FROM avg_sbp_per_stay
)

-- Get the percentile for 160 mmHg
SELECT
  percentile * 100 AS percentile_160_mmhg
FROM percentiles
WHERE avg_sbp = 160;