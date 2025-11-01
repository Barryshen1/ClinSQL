WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 67 AND 77
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.admission_type = 'EMERGENCY'
), CombinedInfo AS (
  SELECT
    pi.subject_id,
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital_expire_flag
  FROM
    PatientInfo AS pi
  INNER JOIN
    AdmissionInfo AS ai
  ON
    pi.subject_id = ai.subject_id
), LOSCalculation AS (
  SELECT
    ci.subject_id,
    ci.hadm_id,
    ci.dischtime,
    ci.deathtime,
    ci.hospital_expire_flag,
    CASE
      WHEN ci.deathtime IS NOT NULL
      THEN TIMESTAMP_DIFF(ci.deathtime, ci.admittime, DAY)
      ELSE TIMESTAMP_DIFF(ci.dischtime, ci.admittime, DAY)
    END AS los
  FROM
    CombinedInfo AS ci
), DischargeStatus AS (
  SELECT
    lc.subject_id,
    lc.hadm_id,
    lc.los,
    CASE
      WHEN lc.hospital_expire_flag = 1
      THEN 'died'
      ELSE 'alive'
    END AS discharge_status
  FROM
    LOSCalculation AS lc
), LOSGroups AS (
  SELECT
    ds.subject_id,
    ds.hadm_id,
    ds.discharge_status,
    ds.los,
    CASE
      WHEN ds.los >= 7
      THEN 1
      ELSE 0
    END AS los_ge_7,
    CASE
      WHEN ds.los >= 14
      THEN 1
      ELSE 0
    END AS los_ge_14
  FROM
    DischargeStatus AS ds
), LOSPercentile AS (
  SELECT
    lg.subject_id,
    lg.hadm_id,
    lg.discharge_status,
    lg.los,
    PERCENTILE_CONT(lg.los, 0.1) OVER (PARTITION BY lg.discharge_status) AS percentile_rank_10_day_los
  FROM
    LOSGroups AS lg
)
SELECT
  discharge_status,
  COUNT(CASE WHEN los_ge_7 = 1 THEN subject_id END) * 100.0 / COUNT(subject_id) AS proportion_los_ge_7,
  COUNT(CASE WHEN los_ge_14 = 1 THEN subject_id END) * 100.0 / COUNT(subject_id) AS proportion_los_ge_14,
  AVG(percentile_rank_10_day_los) AS percentile_rank_10_day_los
FROM
  LOSPercentile AS lp
GROUP BY
  discharge_status;