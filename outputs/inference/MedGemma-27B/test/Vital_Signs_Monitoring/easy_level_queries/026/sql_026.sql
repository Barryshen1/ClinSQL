WITH relevant_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 39 AND 49
),
icu_admissions AS (
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    relevant_patients AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic ON a.hadm_id = ic.hadm_id
),
respiratory_rates AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.intime,
    ce.charttime,
    ce.valuenum AS respiratory_rate
  FROM
    icu_admissions AS icu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON icu.subject_id = ce.subject_id AND icu.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220187 -- Respiratory Rate itemid
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT
  MIN(respiratory_rates.respiratory_rate) AS min_respiratory_rate
FROM
  respiratory_rates;