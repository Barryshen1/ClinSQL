WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 71 AND 81
),
PatientICUStays AS (
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.subject_id IN (SELECT subject_id FROM PatientAge)
),
MaxDBPPerStay AS (
  SELECT
    ps.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    PatientICUStays AS ps
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ps.stay_id = ce.stay_id
  WHERE
    ce.itemid = 455 -- Diastolic Blood Pressure
  GROUP BY
    ps.stay_id
)
SELECT
  PERCENTILE_CONT(0.5, max_dbp) AS median_max_dbp
FROM
  MaxDBPPerStay;