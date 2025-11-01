WITH PatientCohort AS (
  -- Select patients meeting the initial criteria
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.insurance,
    d.long_title AS primary_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1 -- Principal diagnosis
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'ED'
    AND a.insurance = 'Medicare'
    AND d.icd_code LIKE '57%' -- Lower GI bleeding ICD-10 codes start with 57
), Readmission AS (
  -- Identify readmissions within 30 days
  SELECT
    pc.subject_id,
    pc.admittime AS initial_admittime,
    pc.dischtime AS initial_dischtime,
    a2.admittime AS readmission_admittime,
    a2.dischtime AS readmission_dischtime
  FROM
    PatientCohort AS pc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON pc.subject_id = a2.subject_id
  WHERE
    a2.admittime > pc.dischtime
    AND a2.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
), ReadmissionLOS AS (
  -- Calculate LOS for readmissions
  SELECT
    subject_id,
    initial_admittime,
    initial_dischtime,
    readmission_admittime,
    readmission_dischtime,
    TIMESTAMP_DIFF(readmission_dischtime, readmission_admittime, DAY) AS readmission_los
  FROM
    Readmission
), CohortWithReadmissionStatus AS (
  -- Combine initial cohort with readmission status
  SELECT
    pc.subject_id,
    pc.admittime AS initial_admittime,
    pc.dischtime AS initial_dischtime,
    CASE
      WHEN r.subject_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted_flag,
    r.readmission_los
  FROM
    PatientCohort AS pc
  LEFT JOIN
    ReadmissionLOS AS r
    ON pc.subject_id = r.subject_id
), LOSCalculation AS (
  -- Calculate LOS for initial admissions
  SELECT
    subject_id,
    initial_admittime,
    initial_dischtime,
    readmitted_flag,
    readmission_los,
    TIMESTAMP_DIFF(initial_dischtime, initial_admittime, DAY) AS initial_los
  FROM
    CohortWithReadmissionStatus
)
-- Final calculations
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  SUM(CASE WHEN readmitted_flag = 1 THEN 1 ELSE 0 END) AS readmitted_patients,
  (SUM(CASE WHEN readmitted_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id)) * 100 AS readmission_rate_30_day,
  AVG(CASE WHEN readmitted_flag = 1 THEN initial_los ELSE NULL END) AS median_los_readmitted,
  AVG(CASE WHEN readmitted_flag = 0 THEN initial_los ELSE NULL END) AS median_los_not_readmitted,
  (SUM(CASE WHEN initial_los > 6 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id)) * 100 AS percent_los_greater_than_6_days
FROM
  LOSCalculation;