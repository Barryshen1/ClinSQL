WITH PatientCohort AS (
  -- Select subject_id for patients matching the criteria:
  -- 1. Age 48-58
  -- 2. Female gender
  -- 3. Diagnosis of Diabetes (ICD-10 codes E10-E14)
  -- 4. Diagnosis of Heart Failure (ICD-10 codes I50, I11.0, I11.1, I11.9, I13.0, I13.1, I13.2, I50.9)
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code IN ('E10', 'E11', 'E12', 'E13', 'E14', 'I50', 'I11.0', 'I11.1', 'I11.9', 'I13.0', 'I13.1', 'I13.2', 'I50.9')
),

MedicationStarts AS (
  -- Identify starts of subcutaneous GLP-1 agonists within the first 24 hours of admission
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    m.charttime,
    m.medication
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS m
    ON p.hadm_id = m.hadm_id
  WHERE
    m.medication LIKE '%GLP-1%'
    AND m.medication LIKE '%subcutaneous%'
    AND m.charttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
),

MedicationEnds AS (
  -- Identify ends of subcutaneous GLP-1 agonists within the final 12 hours of admission
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    m.charttime,
    m.medication
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS m
    ON p.hadm_id = m.hadm_id
  WHERE
    m.medication LIKE '%GLP-1%'
    AND m.medication LIKE '%subcutaneous%'
    AND m.charttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 12 HOUR) AND p.dischtime
)

-- Calculate the prevalence of starts and ends
SELECT
  COUNT(DISTINCT CASE WHEN ms.subject_id IS NOT NULL THEN ms.subject_id END) * 100.0 / COUNT(DISTINCT pc.subject_id) AS start_prevalence_percent,
  COUNT(DISTINCT CASE WHEN me.subject_id IS NOT NULL THEN me.subject_id END) * 100.0 / COUNT(DISTINCT pc.subject_id) AS end_prevalence_percent
FROM
  PatientCohort AS pc
LEFT JOIN
  MedicationStarts AS ms
  ON pc.subject_id = ms.subject_id
LEFT JOIN
  MedicationEnds AS me
  ON pc.subject_id = me.subject_id;