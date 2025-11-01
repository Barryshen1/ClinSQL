WITH HHS_Patients AS (
  -- Identify patients admitted with HHS
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 73
    AND d.icd_code = '250.2' -- HHS ICD-10 code
),

HHS_Group AS (
  -- Filter HHS patients within the specified age range
  SELECT
    h.subject_id,
    h.hadm_id
  FROM HHS_Patients AS h
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON h.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 68 AND 78
),

All_Patients AS (
  -- Identify all inpatients
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
),

Medication_Complexity AS (
  -- Calculate medication complexity for each patient admission
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS medication_complexity
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY
    hadm_id
),

Hyperkalemia_Risk_Drugs AS (
  -- Identify drugs with hyperkalemia risk
  SELECT DISTINCT
    p.hadm_id,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug IN ('Spironolactone', 'Eplerenone', 'Amiloride', 'Triamterene', 'Potassium Chloride', 'ACE Inhibitors', 'ARBs', 'NSAIDs', 'Heparin')
),

Hyperkalemia_Risk_Score AS (
  -- Calculate percentile rank of patients with hyperkalemia risk drugs
  SELECT
    hadm_id,
    PERCENTILE_CONT(0.5) OVER (PARTITION BY hadm_id) AS median_percentile_rank
  FROM Hyperkalemia_Risk_Drugs
),

LOS_Mortality AS (
  -- Calculate LOS and mortality for each patient admission
  SELECT
    hadm_id,
    a.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
)

-- Final query to combine the results
SELECT
  CASE
    WHEN hg.hadm_id IS NOT NULL THEN 'HHS Group'
    ELSE 'All Inpatients'
  END AS patient_group,
  mc.medication_complexity,
  hr.median_percentile_rank,
  COUNT(DISTINCT CASE WHEN hr.hadm_id IS NOT NULL THEN hr.hadm_id END) / COUNT(DISTINCT hadm_id) AS percent_affected,
  PERCENTILE_CONT(0.75, lm.los) AS top_quartile_los,
  AVG(CASE WHEN lm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality
FROM HHS_Group AS hg
LEFT JOIN Medication_Complexity AS mc
  ON hg.hadm_id = mc.hadm_id
LEFT JOIN Hyperkalemia_Risk;