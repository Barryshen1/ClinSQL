WITH PatientCohort AS (
  -- Identify patients with hemorrhagic stroke (ICD-10 code I60-I69)
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code LIKE 'I6%' -- Hemorrhagic stroke codes (I60-I69)
),
ControlCohort AS (
  -- Identify age-matched controls (female, 48-58, no hemorrhagic stroke)
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    AND d.icd_code LIKE 'I6%' -- Hemorrhagic stroke codes
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code IS NULL -- Exclude patients with hemorrhagic stroke
),
CombinedCohort AS (
  SELECT
    *
  FROM PatientCohort
  UNION ALL
  SELECT
    *
  FROM ControlCohort
),
MedicationComplexity AS (
  -- Calculate medication complexity (number of unique drugs) in the first 48 hours
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT e.drug) AS medication_complexity
  FROM CombinedCohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id
),
Outcomes AS (
  -- Calculate LOS and mortality
  SELECT
    c.subject_id,
    c.hadm_id,
    a.los,
    a.hospital_expire_flag
  FROM CombinedCohort AS c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON c.hadm_id = a.hadm_id
),
SerotonergicDrugs AS (
  -- Identify serotonergic drugs (example list, needs refinement)
  SELECT DISTINCT
    e.subject_id,
    e.hadm_id,
    e.drug
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS e
  WHERE
    e.drug IN ('FLUOXETINE', 'SERTRAINE', 'ESCITLOPRAM', 'PAROXETINE', 'VENLAFAXINE', 'CITALOPRAM', 'FLUVOXAMINE', 'TRAMADOL', 'SUMATRIPTAN', 'LINEZOLID') -- Example list
),
SerotonergicDrugCount AS (
  -- Count serotonergic drugs per patient
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT sd.drug) AS serotonergic_drug_count;