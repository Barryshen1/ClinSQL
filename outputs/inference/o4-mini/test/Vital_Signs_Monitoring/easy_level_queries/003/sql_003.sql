WITH male_icustays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    ic.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

stay_mean_hr AS (
  SELECT
    ci.stay_id,
    AVG(ci.valuenum) AS mean_hr
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ci
  JOIN
    male_icustays m
  ON
    ci.stay_id = m.stay_id
    AND ci.subject_id = m.subject_id
    AND ci.hadm_id = m.hadm_id
  WHERE
    ci.itemid = 220045
    AND ci.valuenum IS NOT NULL
  GROUP BY
    ci.stay_id
)

SELECT
  -- The 50th percentile (median) of the per-stay mean heart rates
  APPROX_QUANTILES(mean_hr, 100)[OFFSET(50)] AS median_per_stay_mean_hr
FROM
  stay_mean_hr;