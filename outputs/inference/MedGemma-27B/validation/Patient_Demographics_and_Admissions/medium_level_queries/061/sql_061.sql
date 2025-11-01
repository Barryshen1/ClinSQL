WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 86 AND 96
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientAge AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND a.insurance = 'Medicare'
), StayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    AdmissionInfo AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
), DischargeOutcome AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.anchor_age,
    s.stay_id,
    s.los,
    CASE
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'LTC') THEN 'Facility'
      WHEN a.hospital_expire_flag = TRUE THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    StayInfo AS s
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON s.hadm_id = a.hadm_id
), StayPercentile AS (
  SELECT
    do.subject_id,
    do.hadm_id,
    do.anchor_age,
    do.stay_id,
    do.los,
    do.discharge_outcome,
    PERCENTILE_CONT(do.los, 0.10) OVER (PARTITION BY do.discharge_outcome) AS percentile_10_stay
  FROM
    DischargeOutcome AS do
)
SELECT
  discharge_outcome,
  AVG(los) AS mean_los,
  MEDIAN(los) AS median_los,
  PERCENTILE_CONT(los, 0.75) AS p75_los,
  PERCENTILE_CONT(los, 0.90) AS p90_los,
  AVG(percentile_10_stay) AS avg_percentile_10_stay
FROM
  StayPercentile
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;