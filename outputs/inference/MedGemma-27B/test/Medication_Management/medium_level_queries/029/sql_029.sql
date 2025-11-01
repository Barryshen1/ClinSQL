WITH PatientCohort AS (
  -- Select subject_ids of patients matching the criteria:
  -- 1. Age 69-79
  -- 2. Female gender
  -- 3. Diagnosis of T2DM (ICD-10 code E11.9)
  -- 4. Diagnosis of Heart Failure (ICD-10 codes I50.9, I50.2, I50.3, I50.4)
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND d.icd_code IN ('E11.9', 'I50.9', 'I50.2', 'I50.3', 'I50.4')
),

MedicationEvents AS (
  -- Select relevant medication events from emar and prescriptions tables
  SELECT
    subject_id,
    hadm_id,
    charttime,
    medication,
    drug_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  UNION ALL
  SELECT
    subject_id,
    hadm_id,
    starttime AS charttime,
    drug AS medication,
    drug_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

DrugClassMapping AS (
  -- Map medications to drug classes
  SELECT
    subject_id,
    hadm_id,
    charttime,
    CASE
      WHEN LOWER(medication) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(medication) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(medication) LIKE '%sulfonylurea%' THEN 'sulfonylurea'
      WHEN LOWER(medication) LIKE '%dpp-4%' THEN 'DPP-4'
      WHEN LOWER(medication) LIKE '%sglt2%' THEN 'SGLT2'
      WHEN LOWER(medication) LIKE '%glp-1%' THEN 'GLP-1'
      WHEN LOWER(medication) LIKE '%tzd%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    MedicationEvents
),

TimeWindows AS (
  -- Define the first and last 72 hours for each admission
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS admission_time,
    MAX(charttime) AS discharge_time
  FROM
    MedicationEvents
  GROUP BY
    subject_id,
    hadm_id
),

First72Hours AS (
  -- Select medication events within the first 72 hours
  SELECT
    dm.subject_id,
    dm.hadm_id,
    dm.drug_class
  FROM
    DrugClassMapping AS dm
  JOIN
    TimeWindows AS tw
    ON dm.subject_id = tw.subject_id AND dm.hadm_id = tw.hadm_id
  WHERE
    dm.charttime BETWEEN tw.admission_time AND TIMESTAMP_ADD(tw.admission_time, INTERVAL 72 HOUR)
),

Last72Hours AS (
  -- Select medication events within the last 72 hours
  SELECT
    dm.subject_id,
    dm.hadm_id,
    dm.drug_class
  FROM
    DrugClassMapping AS dm
  JOIN
    TimeWindows AS tw
    ON dm.subject_id = tw.subject_id AND dm.hadm_id = tw.hadm_id
  WHERE
    dm.charttime BETWEEN TIMESTAMP_SUB(tw.discharge_time, INTERVAL 72 HOUR) AND tw.discharge_time
),

First72HoursCounts AS (
  -- Count the number of patients receiving each drug class in the first 72 hours
  SELECT
    drug_class,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    First72Hours
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    drug_class
),;