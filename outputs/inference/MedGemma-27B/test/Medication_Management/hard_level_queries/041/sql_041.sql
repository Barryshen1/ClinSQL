WITH PatientHF AS (
  -- Identify patients with heart failure diagnosis
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
),

MedicationComplexity AS (
  -- Calculate medication complexity score for each patient admission
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON a.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY
    a.subject_id,
    a.hadm_id
),

PatientData AS (
  -- Combine patient demographics, HF status, and medication complexity
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    mc.hadm_id,
    mc.medication_complexity_score,
    a.dischtime,
    a.deathtime,
    a.admission_type
  FROM PatientHF AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN MedicationComplexity AS mc
    ON p.subject_id = mc.subject_id
  WHERE
    a.hospital_expire_flag = 0 -- Exclude patients who died in hospital
),

Quintiles AS (
  -- Assign patients to quintiles based on medication complexity score
  SELECT
    subject_id,
    hadm_id,
    medication_complexity_score,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS complexity_quintile
  FROM PatientData
),

LOS AS (
  -- Calculate length of stay for each admission
  SELECT
    hadm_id,
    subject_id,
    complexity_quintile,
    medication_complexity_score,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM PatientData
  JOIN Quintiles AS q
    ON PatientData.subject_id = q.subject_id
    AND PatientData.hadm_id = q.hadm_id
),

Mortality AS (
  -- Determine in-hospital mortality
  SELECT
    hadm_id,
    subject_id,
    complexity_quintile,
    medication_complexity_score,
    CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality
  FROM PatientData
  JOIN Quintiles AS q
    ON PatientData.subject_id = q.subject_id
    AND PatientData.hadm_id = q.hadm_id
),

Readmission AS (
  -- Determine 30-day readmission
  SELECT
    p.subject_id,
    p.hadm_id,
    p.complexity_quintile,
    p.medication_complexity_score,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = p.subject_id
        AND a2.admittime BETWEEN TIMESTAMP_ADD(p.dischtime, INTERVAL 30 DAY) AND TIMESTAMP_ADD(p.dischtime, INTERVAL 31 DAY)
    ) THEN 1 ELSE 0 END AS readmission_30_day
  FROM PatientData AS p
  JOIN Quintiles AS q
    ON p.subject_id = q.subject_id
    AND p.hadm_id = q.had;