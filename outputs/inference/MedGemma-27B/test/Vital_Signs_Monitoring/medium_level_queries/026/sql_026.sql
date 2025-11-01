WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 68 AND 78
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  INNER JOIN
    PatientAge AS pa
    ON s.subject_id = pa.subject_id
), RespiratoryRate AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.charttime,
    s.valuenum AS respiratory_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS s
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON s.itemid = d.itemid
  WHERE
    d.label = 'Respiratory Rate' AND s.valuenum IS NOT NULL
), First48HoursRR AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.respiratory_rate
  FROM
    RespiratoryRate AS s
  INNER JOIN
    ICUStays AS i
    ON s.subject_id = i.subject_id AND s.stay_id = i.stay_id
  WHERE
    s.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
), AvgRR AS (
  SELECT
    subject_id,
    stay_id,
    AVG(respiratory_rate) AS avg_respiratory_rate
  FROM
    First48HoursRR
  GROUP BY
    subject_id,
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_respiratory_rate, 0.5) AS median_avg_rr
FROM
  AvgRR
WHERE
  avg_respiratory_rate = 12;