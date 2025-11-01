WITH ARDS_Patients AS (
  -- Identify patients with ARDS based on ICD-10 codes
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.icd_code = 'J80' -- ARDS ICD-10 code
),

Instability_Scores AS (
  -- Calculate instability scores for each patient in the first 72 hours
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Calculate instability score based on vital signs (example: HR, RR, BP)
    -- This is a placeholder calculation, replace with actual instability score logic
    (
      CASE
        WHEN ce.itemid = 3001 THEN (ce.valuenum - 60) / 10 -- Heart Rate deviation from 60
        WHEN ce.itemid = 44818 THEN (ce.valuenum - 12) / 10 -- Respiratory Rate deviation from 12
        WHEN ce.itemid = 455 THEN (ce.valuenum - 120) / 20 -- Systolic BP deviation from 120
        ELSE 0
      END
    ) AS instability_score,
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.chartevents` AS ce
    ON a.hadm_id = ce.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM ARDS_Patients)
    AND ce.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND ce.itemid IN (3001, 44818, 455) -- Example itemids for HR, RR, SBP
),

Percentile_Threshold AS (
  -- Calculate the 90th percentile instability score
  SELECT
    PERCENTILE_CONT(instability_score, 0.90) AS percentile_90
  FROM Instability_Scores
),

High_Instability_Patients AS (
  -- Identify patients with instability scores at or above the 90th percentile
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN Instability_Scores AS is_
    ON a.hadm_id = is_.hadm_id
  JOIN Percentile_Threshold AS pt
    ON is_.instability_score >= pt.percentile_90
  WHERE
    a.subject_id IN (SELECT subject_id FROM ARDS_Patients)
),

General_Inpatients AS (
  -- Select general inpatients for comparison
  SELECT
    p.subject_id,
    p.gender,;