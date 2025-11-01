WITH
-- Step 1: Identify the cohort of female patients, aged 48-58, with diagnoses of both Diabetes and Heart Failure.
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'F'
    -- Calculate age at admission and filter for the specified range
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age BETWEEN 48 AND 58
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    -- Check for presence of at least one diabetes diagnosis (ICD-9 and ICD-10)
    SUM(CASE
      WHEN SUBSTR(dx.icd_code, 1, 3) = '250' OR dx.icd_code LIKE 'E08%' OR dx.icd_code LIKE 'E09%' OR dx.icd_code LIKE 'E10%' OR dx.icd_code LIKE 'E11%' OR dx.icd_code LIKE 'E13%'
      THEN 1 ELSE 0
    END) > 0
    -- Check for presence of at least one heart failure diagnosis (ICD-9 and ICD-10)
    AND SUM(CASE
      WHEN SUBSTR(dx.icd_code, 1, 3) = '428' OR dx.icd_code LIKE 'I50%'
      THEN 1 ELSE 0
    END) > 0
),

-- Step 2: Find the first subcutaneous GLP-1 prescription start time for each hospital admission.
first_glp1_starts AS (
  SELECT
    hadm_id,
    MIN(starttime) AS first_glp1_starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- Filter for common GLP-1 agonists
    (
      LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%lixisenatide%'
    )
    -- Filter for subcutaneous route
    AND LOWER(route) = 'sc'
  GROUP BY
    hadm_id
),

-- Step 3: Join the cohort with GLP-1 starts and create flags for the specified time windows.
analysis_data AS (
  SELECT
    c.hadm_id,
    -- Flag is 1 if the GLP-1 start occurred within the first 24 hours of admission
    CASE
      WHEN fgs.first_glp1_starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
      THEN 1
      ELSE 0
    END AS start_in_first_24h,
    -- Flag is 1 if the GLP-1 start occurred within the final 12 hours before discharge
    CASE
      WHEN fgs.first_glp1_starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
      THEN 1
      ELSE 0
    END AS start_in_final_12h
  FROM
    cohort_admissions AS c
  LEFT JOIN
    first_glp1_starts AS fgs
    ON c.hadm_id = fgs.hadm_id
)

-- Step 4: Calculate the final prevalence percentages from the prepared data.
SELECT
  ROUND((SUM(start_in_first_24h) * 100.0) / COUNT(hadm_id), 2) AS prevalence_pct_first_24h,
  ROUND((SUM(start_in_final_12h) * 100.0) / COUNT(hadm_id), 2) AS prevalence_pct_final_12h,
  COUNT(hadm_id) AS total_cohort_admissions
FROM
  analysis_data;