WITH
-- Define age range and gender
patient_demographics AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN -1 AND 1  -- Ensure age is correct at admission
),

-- Identify patients with diabetes and acute HF
patients_with_conditions AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    pd.admittime,
    pd.dischtime,
    pd.admission_duration_hours
  FROM
    patient_demographics pd
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE
        di.subject_id = pd.subject_id
        AND di.hadm_id = pd.hadm_id
        AND (
          -- Diabetes ICD codes (E11.x, E13.x, etc.)
          (dicd.icd_code LIKE 'E11%' OR dicd.icd_code LIKE 'E13%')
          -- Acute HF ICD codes (I50.x)
          OR dicd.icd_code LIKE 'I50%'
        )
    )
),

-- Identify GLP-1 medications (using common names)
glp1_medications AS (
  SELECT DISTINCT
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%albiglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
),

-- Get all GLP-1 prescriptions with timing
glp1_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    -- Flag if prescription started in first 72 hours
    CASE WHEN TIMESTAMP_DIFF(p.starttime, a.admittime, HOUR) BETWEEN 0 AND 72 THEN 1 ELSE 0 END AS started_in_first_72h,
    -- Flag if prescription started in final 24 hours
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, p.starttime, HOUR) BETWEEN 0 AND 24 THEN 1 ELSE 0 END AS started_in_final_24h
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    glp1_medications g
  ON
    LOWER(p.drug) = LOWER(g.drug)
  WHERE
    p.subject_id IN (SELECT subject_id FROM patients_with_conditions)
    AND p.hadm_id IN (SELECT hadm_id FROM patients_with_conditions)
),

-- Calculate prevalence and initiation rates
prevalence_and_initiation AS (
  SELECT
    COUNT(DISTINCT pwc.subject_id) AS total_patients,
    -- First 72 hours
    COUNT(DISTINCT CASE WHEN gp.started_in_first_72h = 1 THEN gp.subject_id END) AS patients_with_glp1_first_72h,
    COUNT(DISTINCT CASE WHEN gp.started_in_first_72h = 1 AND NOT EXISTS (
      SELECT 1 FROM glp1_prescriptions gp2
      WHERE gp2.subject_id = gp.subject_id
      AND gp2.hadm_id = gp.hadm_id
      AND gp2.starttime < gp.starttime
    ) THEN gp.subject_id END) AS patients_initiated_glp1_first_72h,
    -- Final 24 hours
    COUNT(DISTINCT CASE WHEN gp.started_in_final_24h = 1 THEN gp.subject_id END) AS patients_with_glp1_final_24h,
    COUNT(DISTINCT CASE WHEN gp.started_in_final_24h = 1 AND NOT EXISTS (
      SELECT 1 FROM glp1_prescriptions gp2
      WHERE gp2.subject_id = gp.subject_id
      AND gp2.hadm_id = gp.hadm_id
      AND gp2.starttime < gp.starttime
    ) THEN gp.subject_id END) AS patients_initiated_glp1_final_24h
  FROM
    patients_with_conditions pwc
  LEFT JOIN
    glp1_prescriptions gp
  ON
    pwc.subject_id = gp.subject_id AND pwc.hadm_id = gp.hadm_id
)

-- Final results
SELECT
  total_patients,
  -- First 72 hours
  patients_with_glp1_first_72h,
  ROUND(patients_with_glp1_first_72h * 100.0 / total_patients, 2) AS prevalence_first_72h_pct,
  patients_initiated_glp1_first_72h,
  ROUND(patients_initiated_glp1_first_72h * 100.0 / total_patients, 2) AS initiation_rate_first_72h_pct,
  -- Final 24 hours
  patients_with_glp1_final_24h,
  ROUND(patients_with_glp1_final_24h * 100.0 / total_patients, 2) AS prevalence_final_24h_pct,
  patients_initiated_glp1_final_24h,
  ROUND(patients_initiated_glp1_final_24h * 100.0 / total_patients, 2) AS initiation_rate_final_24h_pct,
  -- Changes
  (patients_with_glp1_final_24h - patients_with_glp1_first_72h) AS absolute_change_prevalence,
  ROUND((patients_with_glp1_final_24h - patients_with_glp1_first_72h) * 100.0 / NULLIF(patients_with_glp1_first_72h, 0), 2) AS relative_change_prevalence_pct,
  (patients_initiated_glp1_final_24h - patients_initiated_glp1_first_72h) AS absolute_change_initiation,
  ROUND((patients_initiated_glp1_final_24h - patients_initiated_glp1_first_72h) * 100.0 / NULLIF(patients_initiated_glp1_first_72h, 0), 2) AS relative_change_initiation_pct
FROM
  prevalence_and_initiation;