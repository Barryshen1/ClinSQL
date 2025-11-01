WITH patient_demographics AS (
  -- Step 1: Define the patient population (females aged 81-91)
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
relevant_admissions AS (
  -- Step 2: Identify admissions for AMI or Chest Pain
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for AMI and Chest Pain
    (
      icd_version = 9 AND (
        icd_code LIKE '410%' -- Acute Myocardial Infarction
        OR icd_code IN ('78650', '78651', '78659') -- Chest Pain variants
      )
    )
    OR
    -- ICD-10 codes for AMI and Chest Pain
    (
      icd_version = 10 AND (
        icd_code LIKE 'I21%' -- Acute Myocardial Infarction
        OR icd_code IN ('R079', 'R0789') -- Chest Pain variants
      )
    )
),
cohort AS (
  -- Step 3: Combine patient demographics with relevant admissions and calculate LOS
  SELECT
    ad.subject_id,
    ad.hadm_id,
    DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
  INNER JOIN
    patient_demographics AS pd ON ad.subject_id = pd.subject_id
  INNER JOIN
    relevant_admissions AS ra ON ad.hadm_id = ra.hadm_id
),
index_tnt AS (
  -- Step 4: Find the first (index) hs-Troponin T for each admission in our cohort
  SELECT
    le.hadm_id,
    le.valuenum,
    -- Rank measurements by time to find the first one
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  WHERE
    le.hadm_id IN (SELECT hadm_id FROM cohort)
    AND le.itemid = 52598 -- d_labitems: Troponin T, High Sensitivity
    AND le.valuenum IS NOT NULL -- Ensure the value is numeric
)
-- Final Step: Categorize results, and calculate counts, percentages, and mean LOS
SELECT
  -- Categorize the hs-TnT value based on standard female cutoffs (ng/L)
  CASE
    WHEN it.valuenum <= 14 THEN 'Normal'
    WHEN it.valuenum > 14 AND it.valuenum <= 52 THEN 'Borderline'
    WHEN it.valuenum > 52 THEN 'Myocardial Injury'
  END AS tnt_category,
  COUNT(DISTINCT c.hadm_id) AS count_of_admissions,
  ROUND(
    COUNT(DISTINCT c.hadm_id) * 100.0 / SUM(COUNT(DISTINCT c.hadm_id)) OVER (),
    2
  ) AS percentage_of_admissions,
  ROUND(AVG(c.hospital_los_days), 2) AS mean_los_days
FROM
  cohort AS c
INNER JOIN
  index_tnt AS it ON c.hadm_id = it.hadm_id
WHERE
  it.rn = 1 -- Only include the index (first) measurement
GROUP BY
  tnt_category
ORDER BY
  -- Order the results logically
  CASE
    WHEN tnt_category = 'Normal' THEN 1
    WHEN tnt_category = 'Borderline' THEN 2
    WHEN tnt_category = 'Myocardial Injury' THEN 3
  END;