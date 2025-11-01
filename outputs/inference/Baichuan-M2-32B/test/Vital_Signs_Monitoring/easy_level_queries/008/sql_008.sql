WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    (p.anchor_year - p.anchor_age) AS birth_year,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 52 AND 62
),
icu_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    i.stay_id,  -- now from icustays
    ce.charttime,
    ce.valuenum,
    DATE_DIFF(ce.charttime, i.intime, DAY) AS icu_day
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id
    AND c.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.subject_id = ce.subject_id
    AND i.hadm_id = ce.hadm_id
    AND i.stay_id = ce.stay_id
    AND ce.itemid = 220210  -- respiratory rate itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
    AND di.label LIKE '%Respiratory rate%'
    AND di.category = 'Respiratory'
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND DATE_DIFF(ce.charttime, i.intime, DAY) >= 1  -- ICU day 2 or later
)
SELECT
  MAX(valuenum) AS max_respiratory_rate
FROM icu_events;