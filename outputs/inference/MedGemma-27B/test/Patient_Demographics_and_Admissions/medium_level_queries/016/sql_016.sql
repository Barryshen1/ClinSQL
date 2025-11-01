WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 44 AND 54
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    t.careunit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.transfers` AS t
    ON a.hadm_id = t.hadm_id
  WHERE
    t.careunit = 'WARD'
), LOSCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    discharge_location,
    hospital_expire_flag,
    -- Calculate Length of Stay (LOS) in days
    (TIMESTAMP_DIFF(dischtime, admitime, DAY) + 1) AS los
  FROM
    AdmissionInfo
)
SELECT
  discharge_location,
  hospital_expire_flag,
  PERCENTILE_CONT(los, 0.5) AS p50,
  PERCENTILE_CONT(los, 0.75) AS p75,
  PERCENTILE_CONT(los, 0.9) AS p90,
  PERCENTILE_CONT(los, 0.95) AS p95,
  PERCENTILE_CONT(los, 0.07) AS percentile_rank_7_day_stay
FROM
  LOSCalculation
GROUP BY
  discharge_location,
  hospital_expire_flag
ORDER BY
  discharge_location,
  hospital_expire_flag;