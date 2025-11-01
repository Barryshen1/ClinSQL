WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 60-70, mixed shock, ICU stay
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND ic.first_careunit = 'ICU' -- Assuming mixed shock implies ICU admission
),
ShockDiagnosis AS (
  -- Identify patients with mixed shock diagnosis
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN ('R57.1', 'R57.2', 'R57.8', 'R57.9') -- ICD-10 codes for shock
    AND icd_version = 10
),
InstabilityScore AS (
  -- Calculate instability score for each patient within the first 48 hours of ICU stay
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ce.charttime,
    ce.valuenum AS map_value,
    ce.valueuom AS map_uom
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 5061 -- MAP (Mean Arterial Pressure)
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),
HypotensionEvents AS (
  -- Identify hypotension events (MAP < 65)
  SELECT
    subject_id,
    stay_id,
    charttime
  FROM InstabilityScore
  WHERE
    map_value < 65
),
TachycardiaEvents AS (
  -- Identify tachycardia events (HR > 100)
  SELECT
    subject_id,
    stay_id,
    charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  WHERE
    ce.itemid = 3001 -- Heart Rate
    AND ce.valuenum > 100
    AND ce.charttime BETWEEN (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = ce.stay_id) AND TIMESTAMP_ADD((SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = ce.stay_id), INTERVAL 48 HOUR)
),
Cohort AS (
  -- Combine patient cohort and shock diagnosis
  SELECT
    pc.subject_id,
    pc.stay_id,
    pc.intime,
    pc.outtime,
    pc.los
  FROM PatientCohort AS pc
  JOIN ShockDiagnosis AS sd
    ON pc.subject_id = sd.subject_id
),
InstabilityScore48h AS (
  -- Calculate instability score for each patient within the first 48 hours of ICU stay
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ce.charttime,
    ce.valuenum AS map_value,
    ce.valueuom AS map_uom
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.stay_id = ce.stay_id
  WHERE
    ce.itemid =;