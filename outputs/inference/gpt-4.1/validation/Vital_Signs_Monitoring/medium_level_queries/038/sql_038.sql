WITH male_icu_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
),
ventilated_stays AS (
  SELECT DISTINCT
    m.subject_id,
    m.stay_id,
    m.intime
  FROM
    male_icu_patients m
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON m.subject_id = pe.subject_id
      AND m.stay_id = pe.stay_id
  WHERE
    pe.itemid = 225792 -- Mechanical Ventilation
    AND pe.starttime <= DATETIME_ADD(m.intime, INTERVAL 6 HOUR)
    AND pe.endtime >= m.intime
),
sbp_measurements AS (
  SELECT
    v.subject_id,
    v.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    ventilated_stays v
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON v.subject_id = ce.subject_id
      AND v.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (220050, 220179) -- Systolic BP (arterial and non-invasive)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= v.intime
    AND ce.charttime <= DATETIME_ADD(v.intime, INTERVAL 6 HOUR)
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS sbp_25th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS sbp_50th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS sbp_75th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS sbp_iqr
FROM
  sbp_measurements
;