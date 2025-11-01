WITH PatientInfo AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 49
),
FilteredAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS pi
    ON a.subject_id = pi.subject_id
),
AgeGroupAdmissions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime
  FROM
    FilteredAdmissions AS fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON fa.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 44 AND 54
),
HeartRateEvents AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.charttime,
    c.valuenum AS heart_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Heart Rate'
    AND c.valuenum IS NOT NULL
),
First24HoursHeartRate AS (
  SELECT
    hra.subject_id,
    hra.hadm_id,
    hra.charttime,
    hra.heart_rate
  FROM
    HeartRateEvents AS hra
  JOIN
    AgeGroupAdmissions AS aga
    ON hra.subject_id = aga.subject_id
    AND hra.hadm_id = aga.hadm_id
  WHERE
    hra.charttime BETWEEN aga.admittime AND TIMESTAMP_ADD(aga.admittime, INTERVAL 24 HOUR)
)
SELECT
  MIN(heart_rate) AS min_heart_rate
FROM
  First24HoursHeartRate;