WITH ed_female_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.subject_id = i.subject_id
     AND a.hadm_id = i.hadm_id
  WHERE
    a.admission_location = 'EMERGENCY'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
systolic_events AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.valuenum AS sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS e
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS d
      ON e.itemid = d.itemid
    JOIN ed_female_cohort AS c
      ON e.subject_id = c.subject_id
     AND e.hadm_id = c.hadm_id
     AND e.stay_id = c.stay_id
  WHERE
    e.valuenum IS NOT NULL
    AND LOWER(d.label) LIKE '%systolic%'
),
max_sbp_per_stay AS (
  SELECT
    stay_id,
    MAX(sbp) AS max_sbp
  FROM
    systolic_events
  GROUP BY
    stay_id
)
SELECT
  -- Approximate 75th percentile of the maximum SBP across all ICU stays in the cohort
  APPROX_QUANTILES(max_sbp, 100)[OFFSET(75)] AS sbp_75th_percentile
FROM
  max_sbp_per_stay;