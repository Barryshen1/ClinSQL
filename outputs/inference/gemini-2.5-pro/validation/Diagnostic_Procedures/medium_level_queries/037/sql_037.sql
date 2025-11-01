WITH
  -- Step 1: Identify hospital admissions with an AMI diagnosis and classify as primary or secondary.
  ami_diagnoses AS (
    SELECT
      hadm_id,
      -- Classify based on the minimum sequence number of an AMI diagnosis.
      CASE
        WHEN MIN(seq_num) = 1 THEN 'Primary AMI'
        ELSE 'Secondary AMI'
      END AS ami_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      -- Filter for ICD-9 and ICD-10 codes for Acute Myocardial Infarction
      (
        icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410'
      ) OR (
        icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR SUBSTR(icd_code, 1, 3) = 'I22')
      )
    GROUP BY
      hadm_id
  ),

  -- Step 2: Count the number of radiology/CT procedures for each admission.
  imaging_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_imaging_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
      -- CPT codes for Radiology procedures (including CTs, X-Rays, etc.) are in the 7xxxx range.
      hcpcs_cd BETWEEN '70000' AND '79999'
    GROUP BY
      hadm_id
  ),

  -- Step 3: Define the main cohort of patients based on demographics and length of stay.
  patient_cohort AS (
    SELECT
      adm.hadm_id,
      -- Categorize the hospital length of stay in days.
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
        ELSE NULL
      END AS los_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
      -- Filter for male patients.
      pat.gender = 'M'
      -- Calculate age at admission and filter for the 43-53 range.
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 43 AND 53
      -- Ensure admission and discharge times are valid for LOS calculation.
      AND adm.dischtime IS NOT NULL
  )

-- Step 4: Join all the data and calculate the final statistics.
SELECT
  ami.ami_type,
  cohort.los_category,
  APPROX_QUANTILES(COALESCE(img.num_imaging_procedures, 0), 100)[OFFSET(50)] AS median_procedures,
  APPROX_QUANTILES(COALESCE(img.num_imaging_procedures, 0), 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(COALESCE(img.num_imaging_procedures, 0), 100)[OFFSET(75)] AS p75_procedures,
  COUNT(cohort.hadm_id) AS num_admissions
FROM
  patient_cohort AS cohort
  -- Join with AMI diagnoses to include only patients with AMI.
  INNER JOIN ami_diagnoses AS ami
    ON cohort.hadm_id = ami.hadm_id
  -- Left join with imaging counts to include patients with zero procedures.
  LEFT JOIN imaging_counts AS img
    ON cohort.hadm_id = img.hadm_id
WHERE
  -- Filter to include only the specified length of stay categories.
  cohort.los_category IS NOT NULL
GROUP BY
  ami.ami_type,
  cohort.los_category
ORDER BY
  ami.ami_type,
  cohort.los_category;