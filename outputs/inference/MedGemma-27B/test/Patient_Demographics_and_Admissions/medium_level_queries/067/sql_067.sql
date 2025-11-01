WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    s.curr_service
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.services` AS s ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND s.curr_service = 'MEDICINE'
), PatientLOS AS (
  SELECT
    subject_id,
    hadm_id,
    -- Calculate length of stay in days
    (TIMESTAMP_DIFF(dischtime, admittime, DAY) + 1) AS los
  FROM
    PatientInfo
), LOSDistribution AS (
  SELECT
    discharge_location,
    hospital_expire_flag,
    COUNTIF(los >= 7) AS los_ge_7_count,
    COUNTIF(los >= 14) AS los_ge_14_count,
    APPROX_QUANTILES(los, 7) AS los_7day_percentiles
  FROM
    PatientLOS
  GROUP BY
    discharge_location,
    hospital_expire_flag
), Proportions AS (
  SELECT
    discharge_location,
    hospital_expire_flag,
    los_ge_7_count / COUNT(*) AS los_ge_7_prop,
    los_ge_14_count / COUNT(*) AS los_ge_14_prop,
    los_7day_percentiles[OFFSET(6)] AS los_7day_percentile_75
  FROM
    LOSDistribution
  GROUP BY
    discharge_location,
    hospital_expire_flag
)
SELECT
  discharge_location,
  hospital_expire_flag,
  los_ge_7_prop,
  los_ge_14_prop,
  los_7day_percentile_75
FROM
  Proportions
ORDER BY
  discharge_location,
  hospital_expire_flag;