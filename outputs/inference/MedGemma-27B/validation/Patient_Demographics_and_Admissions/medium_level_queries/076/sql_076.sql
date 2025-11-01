WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 83 AND 93
),
Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientAge AS pa
    ON a.subject_id = pa.subject_id
),
LOS AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los
  FROM
    Admissions
)
SELECT
  hospital_expire_flag,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(los, 0.5) AS median_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.9) AS p90_los,
  PERCENTILE_CONT(los, 0.05) AS p5_los,
  PERCENTILE_CONT(los, 0.95) AS p95_los,
  RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los) AS percentile_rank_5_day_los
FROM
  LOS
GROUP BY
  hospital_expire_flag;