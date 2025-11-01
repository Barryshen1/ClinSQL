WITH PatientCohort AS (
  -- Identify patients meeting the criteria: 44-year-old female with T2DM and heart failure, LOS >= 72h
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 44
    AND a.los >= 72
    AND EXISTS (
      -- Check for T2DM diagnosis
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.icd_code = 'E11.9' -- T2DM code
    )
    AND EXISTS (
      -- Check for heart failure diagnosis
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.icd_code LIKE 'I50%' -- Heart failure codes
    )
),
InsulinInitiation AS (
  -- Identify insulin initiation events within the first 72h and final 48h
  SELECT
    pc.subject_id,
    p.starttime,
    p.drug,
    p.route,
    CASE
      WHEN p.drug LIKE '%insulin%'
      AND (p.route LIKE '%subq%' OR p.route LIKE '%SQ%')
      AND (p.drug LIKE '%basal%' OR p.drug LIKE '%glargine%' OR p.drug LIKE '%detemir%' OR p.drug LIKE '%degludec%') THEN 'basal'
      WHEN p.drug LIKE '%insulin%'
      AND (p.route LIKE '%subq%' OR p.route LIKE '%SQ%')
      AND (p.drug LIKE '%bolus%' OR p.drug LIKE '%lispro%' OR p.drug LIKE '%aspart%' OR p.drug LIKE '%glulisine%') THEN 'bolus'
      WHEN p.drug LIKE '%insulin%'
      AND (p.route LIKE '%subq%' OR p.route LIKE '%SQ%')
      AND (p.drug LIKE '%basal%' OR p.drug LIKE '%glargine%' OR p.drug LIKE '%detemir%' OR p.drug LIKE '%degludec%' OR p.drug LIKE '%bolus%' OR p.drug LIKE '%lispro%' OR p.drug LIKE '%aspart%' OR p.drug LIKE '%glulisine%') THEN 'basal-bolus'
      WHEN p.drug LIKE '%insulin%'
      AND (p.route LIKE '%IV%' OR p.route LIKE '%infusion%')
      AND p.drug LIKE '%sliding scale%' THEN 'sliding-scale'
      ELSE NULL
    END AS insulin_type,
    CASE
      WHEN p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) THEN 'first_72h'
      WHEN p.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime THEN 'final_48h'
      ELSE NULL
    END AS time_window
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON pc.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.subject_id = a.subject_id
  WHERE
    p.drug LIKE '%insulin%'
    AND (p.route LIKE '%subq%' OR p.route LIKE '%SQ%' OR p.route LIKE '%IV%' OR p.route LIKE '%infusion%')
),
InitiationCounts AS (
  SELECT
    subject_id,
    insulin_type,
    time_window,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM InsulinInitiation
  WHERE insulin_type IS NOT NULL;