WITH
-- Step 1: Identify the cohort of male patients aged 80-90 admitted with ACS
acs_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    -- Filter for Acute Coronary Syndrome (ACS) diagnoses using both ICD-9 and ICD-10
    AND (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' -- Acute Myocardial Infarction
        OR d.icd_code = '4111'  -- Unstable Angina
      ))
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'I21%'  -- Acute Myocardial Infarction
        OR d.icd_code LIKE 'I22%'  -- Subsequent Myocardial Infarction
        OR d.icd_code = 'I200'   -- Unstable Angina
      ))
    )
),

-- Step 2: Find the first high-sensitivity troponin T (hs-TnT) for each admission
first_hstnt AS (
  SELECT
    hadm_id,
    valuenum,
    -- Rank troponin tests by charttime to identify the first one
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 52598 -- d_labitems: Troponin T, High Sensitivity
    AND valuenum IS NOT NULL -- Ensure the value is numeric for categorization
),

-- Step 3: Join the cohort with their first troponin, categorize it, and calculate LOS
categorized_patients AS (
  SELECT
    acs.hadm_id,
    -- Categorize hs-TnT based on standard clinical cutoffs (in ng/L)
    CASE
      WHEN tnt.valuenum < 14 THEN 'Normal'
      WHEN tnt.valuenum BETWEEN 14 AND 52 THEN 'Borderline'
      WHEN tnt.valuenum > 52 THEN 'Myocardial Injury'
      ELSE NULL
    END AS tnt_category,
    -- Calculate hospital length of stay in fractional days for accuracy
    DATETIME_DIFF(acs.dischtime, acs.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM acs_admissions AS acs
  INNER JOIN first_hstnt AS tnt
    ON acs.hadm_id = tnt.hadm_id
  WHERE
    tnt.rn = 1 -- Ensure we only use the first hs-TnT measurement
)

-- Step 4: Aggregate results by category to get counts, percentages, and mean LOS
SELECT
  tnt_category,
  COUNT(hadm_id) AS patient_count,
  -- Calculate percentage relative to the total number of patients in the final cohort
  ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage,
  ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days
FROM categorized_patients
WHERE
  tnt_category IS NOT NULL
GROUP BY
  tnt_category
ORDER BY
  -- Order results logically: Normal, Borderline, Myocardial Injury
  CASE
    WHEN tnt_category = 'Normal' THEN 1
    WHEN tnt_category = 'Borderline' THEN 2
    WHEN tnt_category = 'Myocardial Injury' THEN 3
  END;