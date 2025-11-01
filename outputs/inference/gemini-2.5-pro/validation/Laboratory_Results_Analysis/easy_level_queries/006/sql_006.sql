WITH PatientCohort AS (
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON pat.subject_id = dx.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age = 50
    -- Filter for ICD codes related to Chronic Obstructive Pulmonary Disease (COPD).
    -- ICD-10 codes for COPD start with J44.
    -- Common ICD-9 codes for COPD include 491 (chronic bronchitis), 492 (emphysema), and 496 (chronic airway obstruction, NEC).
    AND (
      dx.icd_code LIKE 'J44%' -- Chronic obstructive pulmonary disease (ICD-10)
      OR dx.icd_code LIKE '491%' -- Chronic bronchitis (ICD-9)
      OR dx.icd_code LIKE '492%' -- Emphysema (ICD-9)
      OR dx.icd_code LIKE '496'  -- Chronic airway obstruction, not elsewhere classified (ICD-9)
    )
),

-- CTE to calculate the nadir (minimum) serum sodium for each hospital admission.
NadirSodiumPerAdmission AS (
  SELECT
    hadm_id,
    MIN(valuenum) AS nadir_serum_sodium
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    -- itemid for Sodium, Serum (identified from d_labitems)
    itemid IN (50983, 50824)
    AND valuenum IS NOT NULL -- Ensure value is a number for calculation
  GROUP BY
    hadm_id
)

-- Final query to compute the standard deviation of the nadir sodium values for the cohort.
SELECT
  STDDEV_SAMP(ns.nadir_serum_sodium) AS stddev_of_nadir_serum_sodium
FROM NadirSodiumPerAdmission AS ns
-- Join with the patient cohort to filter for relevant admissions only
JOIN PatientCohort AS cohort
  ON ns.hadm_id = cohort.hadm_id;