WITH
-- Get male patients aged 66-76
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 66 AND 76
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients p ON s.subject_id = p.subject_id
),

-- Identify invasively ventilated patients (using common ventilator itemids)
ventilated_patients AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid IN (223849, 223850, 223851) -- Ventilator-related itemids
),

-- Get SBP measurements in the first 6 hours of ICU stay
sbp_measurements AS (
  SELECT
    c.valuenum AS sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    ventilated_patients v ON c.subject_id = v.subject_id AND c.hadm_id = v.hadm_id AND c.stay_id = v.stay_id
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    c.itemid IN (220050, 220179) -- SBP itemids
    AND c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 6 HOUR)
    AND c.valuenum IS NOT NULL
)

-- Calculate IQR of SBP
SELECT
  PERCENTILE_CONT(sbp, 0.25) OVER() AS q1,
  PERCENTILE_CONT(sbp, 0.75) OVER() AS q3,
  PERCENTILE_CONT(sbp, 0.75) OVER() - PERCENTILE_CONT(sbp, 0.25) OVER() AS iqr
FROM
  sbp_measurements
LIMIT 1;