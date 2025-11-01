WITH
  patient_base AS (
    -- Step 1: Identify the base cohort of patients and admissions based on demographics and length of stay
    SELECT
      p.subject_id,
      a.hadm_id,
      -- Stratify by length of stay (LOS)
      CASE
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4
          THEN '1-4 day stay'
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7
          THEN '5-7 day stay'
      END AS los_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 83 AND 93
      -- Filter for the LOS ranges of interest to avoid extra processing
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  ),

  acs_admissions AS (
    -- Step 2: Identify all admissions with a diagnosis of Acute Coronary Syndrome (ACS)
    SELECT
      hadm_id,
      seq_num
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- ICD-9 codes for ACS (Acute Myocardial Infarction, Unstable Angina)
      (
        icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '4111%')
      )
      -- ICD-10 codes for ACS (Unstable Angina, MI)
      OR (
        icd_version = 10 AND (icd_code LIKE 'I200%' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')
      )
  ),

  cohort_stratified AS (
    -- Step 3: Combine cohort with ACS diagnoses and stratify by primary vs. secondary diagnosis
    SELECT
      pb.hadm_id,
      pb.los_category,
      -- If the minimum sequence number for an ACS code is 1, it's a primary diagnosis for that admission
      CASE
        WHEN MIN(aa.seq_num) = 1 THEN 'Primary Diagnosis'
        ELSE 'Secondary Diagnosis'
      END AS diagnosis_type
    FROM
      patient_base AS pb
    JOIN
      acs_admissions AS aa
      ON pb.hadm_id = aa.hadm_id
    GROUP BY
      pb.hadm_id,
      pb.los_category
  ),

  ultrasound_codes AS (
    -- Step 4a: Create a reference list of all ultrasound-related procedure codes
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%ultrasound%' OR LOWER(long_title) LIKE '%echocardiography%'
  ),

  ultrasound_counts AS (
    -- Step 4b: Count the number of ultrasound procedures for each admission
    SELECT
      p.hadm_id,
      COUNT(p.icd_code) AS ultrasound_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    JOIN
      ultrasound_codes AS uc
      ON p.icd_code = uc.icd_code AND p.icd_version = uc.icd_version
    GROUP BY
      p.hadm_id
  )

-- Step 5: Final aggregation to calculate mean, min, and max ultrasounds per admission
SELECT
  cs.los_category,
  cs.diagnosis_type,
  COUNT(DISTINCT cs.hadm_id) AS num_admissions,
  -- Use COALESCE to treat admissions with no ultrasounds as 0
  AVG(COALESCE(uc.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(uc.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(uc.ultrasound_count, 0)) AS max_ultrasounds
FROM
  cohort_stratified AS cs
LEFT JOIN
  ultrasound_counts AS uc
  ON cs.hadm_id = uc.hadm_id
GROUP BY
  cs.los_category,
  cs.diagnosis_type
ORDER BY
  cs.los_category,
  cs.diagnosis_type;