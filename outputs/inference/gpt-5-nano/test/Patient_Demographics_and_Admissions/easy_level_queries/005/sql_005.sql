WITH dialysis_subjects AS (
  -- Identify female patients aged 77-87 who had any dialysis-related ICU inputevent
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` AS ie
    ON ie.subject_id = icu.subject_id AND ie.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ie.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND LOWER(di.label) LIKE '%dialysis%'
),
first_stay AS (
  -- For each dialysis patient, take their first ICU stay (earliest intime)
  SELECT
    ds.subject_id,
    icu.intime,
    icu.outtime,
    TIMESTAMP_DIFF(icu.outtime, icu.intime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY ds.subject_id ORDER BY icu.intime) AS rn
  FROM dialysis_subjects ds
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON icu.subject_id = ds.subject_id
  QUALIFY rn = 1
)
SELECT
  (q[OFFSET(3)] - q[OFFSET(1)]) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS q
  FROM first_stay
) t;