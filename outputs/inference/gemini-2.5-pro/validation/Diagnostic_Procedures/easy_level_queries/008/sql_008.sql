WITH
  -- Step 1: Find all ICD codes related to echocardiography
  echo_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%echocardiogra%'
  ),

  -- Step 2: Define the patient cohort: females aged 88-98
  target_patients AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'F'
      AND anchor_age BETWEEN 88 AND 98
  ),

  -- Step 3: Count distinct echo procedures for patients who had at least one
  patient_echo_counts AS (
    SELECT
      proc.subject_id,
      COUNT(DISTINCT proc.icd_code) AS num_distinct_echo_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      echo_codes
      ON proc.icd_code = echo_codes.icd_code AND proc.icd_version = echo_codes.icd_version
    GROUP BY
      proc.subject_id
  ),

  -- Step 4: Create a complete list of all target patients and their echo counts,
  -- including those with zero procedures.
  all_patient_counts AS (
    SELECT
      tp.subject_id,
      COALESCE(pec.num_distinct_echo_procedures, 0) AS num_distinct_echo_procedures
    FROM
      target_patients AS tp
    LEFT JOIN
      patient_echo_counts AS pec
      ON tp.subject_id = pec.subject_id
  )

-- Final Step: Calculate the 25th percentile of the distinct procedure counts
-- for the entire cohort.
SELECT
  APPROX_QUANTILES(num_distinct_echo_procedures, 100)[OFFSET(25)] AS p25_distinct_echo_procedures
FROM
  all_patient_counts;