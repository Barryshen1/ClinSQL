WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    discharge_location,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), CombinedInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM
    AdmissionInfo AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
), FilteredInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    discharge_location,
    hospital_expire_flag,
    gender,
    anchor_age
  FROM
    CombinedInfo
  WHERE
    gender = 'F' AND anchor_age BETWEEN 50 AND 60 AND admission_type = 'EMERGENCY'
), LOSCalculation AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    discharge_location,
    hospital_expire_flag,
    gender,
    anchor_age,
    CASE
      WHEN hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(dischtime, admitime, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admitime, DAY)
    END AS los
  FROM
    FilteredInfo
), DischargeOutcome AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    discharge_location,
    hospital_expire_flag,
    gender,
    anchor_age,
    los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    LOSCalculation
), AggregatedResults AS (
  SELECT
    discharge_outcome,
    AVG(los) AS mean_los,
    STDDEV(los) AS sd_los,
    COUNTIF(los <= 10) / COUNT(los) AS percent_le_10_days
  FROM
    DischargeOutcome
  GROUP BY
    discharge_outcome
)
SELECT
  discharge_outcome,
  mean_los,
  sd_los,
  percent_le_10_days
FROM
  AggregatedResults
ORDER BY
  discharge_outcome;