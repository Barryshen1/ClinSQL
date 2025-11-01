WITH female_elderly_stays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
      USING(subject_id)
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 75 AND 85
),
bp_events AS (
  SELECT
    fs.stay_id,
    ce.valuenum AS sbp,
    ce.charttime,
    fs.intime
  FROM
    female_elderly_stays AS fs
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON fs.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (220050, 220179)  -- non-invasive and arterial systolic BP
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN fs.intime
                        AND TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
),
per_stay_mean AS (
  SELECT
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM
    bp_events
  GROUP BY
    stay_id
)
SELECT
  100.0 * COUNTIF(mean_sbp <= 140) / COUNT(*) AS percentile_of_140
FROM
  per_stay_mean;