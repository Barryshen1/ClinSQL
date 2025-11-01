WITH female_age_group AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
hr_events AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
)
, first_hr_per_stay AS (
  SELECT
    f.subject_id,
    f.stay_id,
    hr.valuenum AS first_hr
  FROM
    female_age_group f
  INNER JOIN
    hr_events hr
    ON f.subject_id = hr.subject_id
    AND f.stay_id = hr.stay_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY f.stay_id ORDER BY hr.charttime) = 1
)
SELECT
  MIN(first_hr) AS min_first_recorded_hr
FROM
  first_hr_per_stay;