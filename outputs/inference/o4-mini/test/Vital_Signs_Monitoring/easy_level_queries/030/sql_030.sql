WITH eligible_stays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
      ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 38 AND 48
),
first_hr_per_stay AS (
  SELECT
    es.stay_id,
    ce.charttime,
    ce.valuenum AS heart_rate
  FROM
    eligible_stays AS es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON es.subject_id = ce.subject_id
     AND es.hadm_id = ce.hadm_id
     AND es.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY ce.charttime) = 1
)
SELECT
  MIN(heart_rate) AS min_first_recorded_heart_rate
FROM
  first_hr_per_stay;