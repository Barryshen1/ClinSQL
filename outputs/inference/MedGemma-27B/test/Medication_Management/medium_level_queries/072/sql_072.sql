WITH
  -- Identify patients with type 2 diabetes and heart failure
  patients_with_conditions AS (
    SELECT DISTINCT
      p.subject_id,
      p.gender,
      p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 79 AND 89
      AND d.icd_code IN ('E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.0', 'E11.1') -- Type 2 Diabetes codes
      AND d.icd_code IN ('I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.0', 'I50.5', 'I50.7') -- Heart Failure codes
  ),
  -- Identify GLP-1 receptor agonist medications
  glp1_medications AS (
    SELECT DISTINCT
      p.subject_id,
      p.hadm_id,
      p.drug,
      p.starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    WHERE
      p.drug LIKE '%glp-1%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%semaglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%exenatide%'
  ),
  -- Calculate the time difference between admission and medication start time
  medication_timing AS (
    SELECT
      g.subject_id,
      g.hadm_id,
      a.admittime,
      g.drug,
      g.starttime
    FROM glp1_medications AS g
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON g.subject_id = a.subject_id AND g.hadm_id = a.hadm_id
  ),
  -- Calculate the time difference between medication start time and discharge time
  medication_timing_discharge AS (
    SELECT
      m.subject_id,
      m.hadm_id,
      m.admittime,
      m.starttime,
      a.dischtime
    FROM medication_timing AS m
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
  ),
  -- Calculate the time difference between admission and medication start time in hours
  medication_timing_hours AS (
    SELECT
      subject_id,
      hadm_id,
      TIMESTAMP_DIFF(starttime, admittime, HOUR) AS time_diff_hours
    FROM medication_timing_discharge
  ),
  -- Calculate the time difference between medication start time and discharge time in;