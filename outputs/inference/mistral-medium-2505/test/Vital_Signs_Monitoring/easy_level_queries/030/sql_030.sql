WITH female_patients_38_48 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission (anchor_age is age at anchor_year)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48
),

icu_stays_with_heart_rate AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    i.stay_id,
    c.charttime,
    c.valuenum AS heart_rate
  FROM
    female_patients_38_48 f
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON f.subject_id = i.subject_id AND f.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id AND i.stay_id = c.stay_id
  WHERE
    c.itemid = 220045  -- Heart rate itemid
    AND c.valuenum IS NOT NULL
),

first_heart_rate_per_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    heart_rate,
    ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id, stay_id ORDER BY charttime) AS rn
  FROM
    icu_stays_with_heart_rate
)

SELECT
  MIN(heart_rate) AS min_first_recorded_heart_rate
FROM
  first_heart_rate_per_stay
WHERE
  rn = 1  -- Only the first recorded heart rate per ICU stay
;