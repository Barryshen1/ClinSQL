WITH female_icu_patients AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
),
heart_rate_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
),
hr_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    fip.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN
    female_icu_patients fip
    ON ce.subject_id = fip.subject_id
    AND ce.stay_id = fip.stay_id
  INNER JOIN
    heart_rate_items hri
    ON ce.itemid = hri.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(ce.charttime, fip.intime, HOUR) >= 24
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS heart_rate_25th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS heart_rate_75th_percentile
FROM
  hr_measurements
;