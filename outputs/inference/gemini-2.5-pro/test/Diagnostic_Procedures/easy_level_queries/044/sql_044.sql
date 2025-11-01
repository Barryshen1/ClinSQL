WITH
  -- Step 1: Define the set of ICD codes for mechanical circulatory support procedures.
  mcs_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%intra-aortic balloon%'
      OR LOWER(long_title) LIKE '%extracorporeal membrane oxygenation%'
      OR LOWER(long_title) LIKE '%heart assist system%'
      OR LOWER(long_title) LIKE '%impella%'
      OR LOWER(long_title) LIKE '%ventricular assist device%'
  ),

  -- Step 2: Identify the patient cohort of interest: males aged 56-66.
  patient_cohort AS (
    SELECT
      subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 56 AND 66
  ),

  -- Step 3: Count the number of distinct MCS procedures for each patient who had at least one.
  patient_mcs_counts AS (
    SELECT
      proc.subject_id,
      COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN mcs_codes AS mcs
      ON proc.icd_code = mcs.icd_code AND proc.icd_version = mcs.icd_version
    -- Ensure we only consider procedures for patients in our cohort.
    WHERE
      proc.subject_id IN (
        SELECT subject_id FROM patient_cohort
      )
    GROUP BY
      proc.subject_id
  )

-- Step 4: Calculate the standard deviation of counts across the entire cohort.
-- This includes patients with zero procedures by using a LEFT JOIN and COALESCE.
SELECT
  STDDEV(COALESCE(pmc.num_distinct_procedures, 0)) AS sd_of_distinct_mcs_procedures
FROM patient_cohort AS pc
LEFT JOIN patient_mcs_counts AS pmc
  ON pc.subject_id = pmc.subject_id;