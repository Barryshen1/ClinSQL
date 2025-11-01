WITH acs_hadm_ids AS (
  -- Step 1: Identify all hospital admissions with an ACS-related diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Acute Myocardial Infarction and Unstable Angina
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
    OR (icd_version = 9 AND icd_code = '4111')
    -- ICD-10 codes for Acute Myocardial Infarction and Unstable Angina
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
    OR (icd_version = 10 AND icd_code = 'I200')
),
patient_cohort AS (
  -- Step 2: Define the patient cohort: females aged 67-77 at admission
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 67 AND 77
),
first_troponin AS (
  -- Step 3: Find the first Troponin T measurement for each hospital admission
  SELECT
    hadm_id,
    valuenum,
    ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 51003 -- Troponin T
    AND valuenum IS NOT NULL
)
-- Step 4: Combine the data, categorize, and calculate final metrics
SELECT
  troponin_category,
  COUNT(hadm_id) AS counts,
  ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER(), 2) AS percent_of_admissions,
  ROUND(AVG(hospital_expire_flag) * 100.0, 2) AS in_hospital_mortality_rate
FROM (
  SELECT
    pc.hadm_id,
    pc.hospital_expire_flag,
    CASE
      WHEN ft.valuenum <= 0.04 THEN 'Normal (<=0.04)'
      WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline (>0.04-0.1)'
      WHEN ft.valuenum > 0.1 THEN 'Elevated (>0.1)'
      ELSE NULL
    END AS troponin_category
  FROM patient_cohort AS pc
  INNER JOIN acs_hadm_ids AS acs
    ON pc.hadm_id = acs.hadm_id
  INNER JOIN first_troponin AS ft
    ON pc.hadm_id = ft.hadm_id
  WHERE
    ft.rn = 1 -- Ensure we only use the first troponin measurement
) AS final_cohort
WHERE
  troponin_category IS NOT NULL
GROUP BY
  troponin_category
ORDER BY
  CASE
    WHEN troponin_category = 'Normal (<=0.04)' THEN 1
    WHEN troponin_category = 'Borderline (>0.04-0.1)' THEN 2
    WHEN troponin_category = 'Elevated (>0.1)' THEN 3
  END;