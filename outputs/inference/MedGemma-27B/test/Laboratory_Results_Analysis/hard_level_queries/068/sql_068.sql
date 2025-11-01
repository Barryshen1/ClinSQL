WITH SepticShockPatients AS (
  -- Identify patients with septic shock based on ICD-9 codes
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND d.icd_code IN ('468.1', '468.2', '468.3', '468.4', '468.5', '468.8', '468.9', '469.0', '469.1', '469.2', '469.3', '469.8', '469.9', '995.92') -- Septic shock ICD-9 codes
),

PatientDemographics AS (
  -- Get patient demographics
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.subject_id IN (SELECT subject_id FROM SepticShockPatients)
),

ICUStays AS (
  -- Get ICU stays for septic shock patients
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (SELECT subject_id FROM SepticShockPatients)
),

InstabilityScore AS (
  -- Calculate the instability score for each patient
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    -- Calculate the instability score based on the provided criteria
    -- This is a placeholder for the actual instability score calculation
    -- Replace this with the actual calculation based on the specific instability score definition
    (
      -- Example calculation: sum of MAP, HR, RR, Temp deviations
      -- This needs to be replaced with the actual instability score formula
      COALESCE(SUM(CASE WHEN c.itemid = 50602 THEN c.valuenum ELSE 0 END), 0) + -- MAP
      COALESCE(SUM(CASE WHEN c.itemid = 3001 THEN c.valuenum ELSE 0 END), 0) + -- HR
      COALESCE(SUM(CASE WHEN c.itemid = 44818 THEN c.valuenum ELSE 0 END), 0) + -- RR
      COALESCE(SUM(CASE WHEN c.itemid = 3141 THEN c.valuenum ELSE 0 END), 0) -- Temp
    ) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON i.stay_id = c.stay_id -- Corrected JOIN condition
  WHERE
    c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR) -- Filter for the first 48 hours
  GROUP BY
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
),

AbnormalLabs AS (
  -- Identify abnormal lab values for septic shock patients
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    CASE
      WHEN l.valuenum < d.ref_range_lower OR l.valuenum > d.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.lab;