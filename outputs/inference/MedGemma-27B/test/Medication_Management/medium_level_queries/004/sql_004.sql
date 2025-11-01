WITH PatientCohort AS (
  -- Select patients meeting the criteria: male, age 45-55, T2DM, heart failure
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.icd_code IN ('E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8') -- T2DM codes
    AND d.icd_code IN ('I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.9') -- Heart failure codes
),
GLP1Orders AS (
  -- Identify GLP-1 medication orders
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%glp-1%' -- Assuming GLP-1 drugs contain 'glp-1' in their name
    OR p.drug LIKE '%semaglutide%'
    OR p.drug LIKE '%liraglutide%'
    OR p.drug LIKE '%dulaglutide%'
    OR p.drug LIKE '%exenatide%'
),
GLP1Usage AS (
  -- Determine if a patient was on GLP-1 within the specified time windows
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE
      WHEN go.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR) THEN 1
      ELSE 0
    END AS started_within_72h,
    CASE
      WHEN go.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 48 HOUR) AND pc.dischtime THEN 1
      ELSE 0
    END AS on_in_last_48h
  FROM PatientCohort AS pc
  JOIN GLP1Orders AS go
    ON pc.subject_id = go.subject_id AND pc.hadm_id = go.hadm_id
)
SELECT
  COUNT(DISTINCT CASE WHEN started_within_72h = 1 THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS pct_started_within_72h,
  COUNT(DISTINCT CASE WHEN on_in_last_48h = 1 THEN subject_id END) * 100.0 / COUNT(DISTINCT subject_id) AS pct_on_in_last_48h,
  SUM(started_within_72h - on_in_last_48h) AS net_change
FROM GLP1Usage;