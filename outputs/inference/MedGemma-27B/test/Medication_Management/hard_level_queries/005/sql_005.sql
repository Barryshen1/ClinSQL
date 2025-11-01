WITH PatientCohort AS (
  -- Select patients matching the criteria: male, age 43-53, hepatic failure diagnosis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.deathtime,
    -- Check for hepatic failure diagnosis (ICD-10 codes)
    CASE WHEN EXISTS (
      SELECT 1
      FROM mimiciv_3_1_hosp.diagnoses_icd AS d
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code IN ('K72.0', 'K72.1', 'K72.2', 'K72.3', 'K72.4', 'K72.9', 'K73.0', 'K73.1', 'K73.2', 'K73.3', 'K73.4', 'K73.5', 'K73.6', 'K73.8', 'K73.9', 'K74.0', 'K74.1', 'K74.2', 'K74.3', 'K74.4', 'K74.5', 'K74.6', 'K74.8', 'K74.9', 'K75.0', 'K75.1', 'K75.2', 'K75.3', 'K75.4', 'K75.8', 'K75.9', 'K76.0', 'K76.1', 'K76.2', 'K76.3', 'K76.4', 'K76.5', 'K76.6', 'K76.7', 'K76.8', 'K76.9')
    ) THEN 1 ELSE 0 END AS has_hepatic_failure
  FROM mimiciv_3_1_hosp.patients AS p
  JOIN mimiciv_3_1_hosp.admissions AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

MedicationComplexity AS (
  -- Calculate medication complexity score for each patient within the first 72 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    COUNT(DISTINCT e.drug) AS medication_complexity_score
  FROM PatientCohort AS pc
  JOIN mimiciv_3_1_hosp.emar AS e
    ON pc.subject_id = e.subject_id
    AND pc.hadm_id = e.hadm_id
    AND e.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.admittime
),

PatientOutcomes AS (
  -- Calculate LOS and mortality for each patient
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.;