WITH PatientCohort AS (
  -- Select patients matching the criteria: male, age 63-73, diagnosed with acute pancreatitis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND d.icd_code LIKE 'K85%' -- ICD-10 code for acute pancreatitis
    AND d.icd_version = 10
    AND a.admittime >= '2150-01-01' -- Filter out future dates
    AND a.admittime < '2024-01-01' -- Filter out future dates
    AND a.dischtime >= a.admittime -- Ensure discharge time is after admission time
  GROUP BY
    p.subject_id,
    a.hadm_id
), LabInstability AS (
  -- Calculate the 72-hour lab instability score for each patient admission
  SELECT
    pc.subject_id,
    pc.hadm_id,
    -- Calculate the 72-hour lab instability score
    SUM(CASE
      WHEN le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR) THEN 1
      ELSE 0
    END) AS lab_instability_score
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id AND pc.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id
), P90Threshold AS (
  -- Calculate the 90th percentile of the lab instability score
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.90) AS p90_threshold
  FROM LabInstability
), CohortP90 AS (
  -- Select patients with a lab instability score >= P90 threshold
  SELECT
    li.subject_id,
    li.hadm_id,
    li.lab_instability_score
  FROM LabInstability AS li
  JOIN P90Threshold AS p90
    ON li.lab_instability_score >= p90.p90_threshold
), GeneralCohort AS (
  -- Select all general inpatients for comparison
  SELECT
    a.subject_id,;