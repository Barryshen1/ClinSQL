WITH
-- Get female patients aged 45-55 at ICU admission
female_patients_45_55 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at ICU admission (anchor_age + (admittime year - anchor_year))
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 45 AND 55
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    -- ICU day 2 start time (intime + 2 days)
    TIMESTAMP_ADD(s.intime, INTERVAL 2 DAY) AS icu_day2_start
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients_45_55 fp
    ON s.subject_id = fp.subject_id AND s.hadm_id = fp.hadm_id
),

-- Get heart rate measurements on ICU day 2+
heart_rates AS (
  SELECT
    c.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s
    ON c.subject_id = s.subject_id
    AND c.hadm_id = s.hadm_id
    AND c.stay_id = s.stay_id
  WHERE
    c.itemid = 220045  -- Heart rate itemid
    AND c.charttime >= s.icu_day2_start
    AND c.charttime <= s.outtime
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0  -- Exclude invalid values
)

-- Calculate IQR of heart rate
SELECT
  PERCENTILE_CONT(heart_rate, 0.25) OVER() AS q1,
  PERCENTILE_CONT(heart_rate, 0.5) OVER() AS median,
  PERCENTILE_CONT(heart_rate, 0.75) OVER() AS q3,
  PERCENTILE_CONT(heart_rate, 0.75) OVER() - PERCENTILE_CONT(heart_rate, 0.25) OVER() AS iqr
FROM
  heart_rates
LIMIT 1;  -- Only need one row for the aggregated result;