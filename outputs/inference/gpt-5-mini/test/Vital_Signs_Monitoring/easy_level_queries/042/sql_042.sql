WITH rr_events AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
       AND icu.subject_id = ce.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND (
      LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%resp rate%'
    )
),

per_stay_max AS (
  -- max respiratory rate per ICU stay (for selected female patients, ages 63-73)
  SELECT
    stay_id,
    subject_id,
    MAX(valuenum) AS max_rr
  FROM rr_events
  GROUP BY stay_id, subject_id
)

SELECT
  COUNT(*) AS n_stays,
  STDDEV_POP(max_rr) AS sd_max_rr
FROM per_stay_max;