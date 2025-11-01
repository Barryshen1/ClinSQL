WITH patient_icu AS (
  SELECT 
    p.subject_id,
    p.anchor_year,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.intime, DATE((p.anchor_year - p.anchor_age), 1, 1), YEAR) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(i.intime, DATE((p.anchor_year - p.anchor_age), 1, 1), YEAR) BETWEEN 35 AND 45
),
respiratory_rates AS (
  SELECT 
    ce.stay_id,
    ce.valuenum
  FROM patient_icu p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON p.subject_id = ce.subject_id
    AND p.stay_id = ce.stay_id
    AND ce.charttime BETWEEN p.intime AND p.outtime
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
    AND di.label LIKE '%Respiratory rate%'
  WHERE ce.valuenum IS NOT NULL
),
max_rr_per_stay AS (
  SELECT 
    stay_id,
    MAX(valuenum) AS max_rr
  FROM respiratory_rates
  GROUP BY stay_id
)
SELECT MIN(max_rr) AS min_max_rr
FROM max_rr_per_stay;