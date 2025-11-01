WITH
-- Get female patients aged 71-81 at admission
female_patients_71_81 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 71 AND 81
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
    female_patients_71_81 fp
  ON
    s.subject_id = fp.subject_id AND s.hadm_id = fp.hadm_id
),

-- Get DBP measurements for these ICU stays
dbp_measurements AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS dbp_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s
  ON
    ce.subject_id = s.subject_id
    AND ce.hadm_id = s.hadm_id
    AND ce.stay_id = s.stay_id
  WHERE
    ce.itemid = 220050  -- Diastolic Blood Pressure
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Filter out unrealistic values
),

-- Calculate maximum DBP per ICU stay
max_dbp_per_stay AS (
  SELECT
    stay_id,
    MAX(dbp_value) AS max_dbp
  FROM
    dbp_measurements
  GROUP BY
    stay_id
)

-- Calculate median of the maximum DBP values across all stays
SELECT
  PERCENTILE_CONT(max_dbp, 0.5) OVER() AS median_max_dbp
FROM
  max_dbp_per_stay
LIMIT 1;