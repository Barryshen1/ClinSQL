WITH female_icustays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),

hr_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS hr,
    ce.charttime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    -- restrict to heart rate measurements
  WHERE
    LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
),

hr_by_stay AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    AVG(e.hr) AS avg_hr
  FROM
    female_icustays f
    JOIN hr_events e
      ON f.subject_id = e.subject_id
     AND f.hadm_id    = e.hadm_id
     AND f.stay_id    = e.stay_id
     -- ensure event falls within the ICU stay
     AND e.charttime BETWEEN f.intime AND f.outtime
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
)

SELECT
  COUNT(*) AS cohort_size,
  100.0 * SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_90
FROM
  hr_by_stay;