WITH
-- Get female patients aged 38-48 at admission
female_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 38 AND 48
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
    female_patients fp
  ON
    s.subject_id = fp.subject_id AND s.hadm_id = fp.hadm_id
),

-- Get SpO2 measurements (itemid 220277 is SpO2 in MIMIC-IV)
spo2_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label = 'SpO2'
    AND ce.valuenum BETWEEN 0 AND 100  -- Filter valid SpO2 values
),

-- Calculate mean SpO2 per ICU stay
mean_spo2_per_stay AS (
  SELECT
    sm.stay_id,
    AVG(sm.spo2_value) AS mean_spo2
  FROM
    spo2_measurements sm
  GROUP BY
    sm.stay_id
),

-- Count total stays and stays with mean SpO2 <= 92
percentile_calculation AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) AS stays_with_spo2_le_92
  FROM
    mean_spo2_per_stay
)

-- Calculate the percentile
SELECT
  stays_with_spo2_le_92,
  total_stays,
  ROUND((stays_with_spo2_le_92 / total_stays) * 100, 2) AS percentile
FROM
  percentile_calculation;