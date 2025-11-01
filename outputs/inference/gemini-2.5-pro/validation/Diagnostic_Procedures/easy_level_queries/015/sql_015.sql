WITH
  -- Identify all ICD codes related to CABG procedures.
  cabg_codes AS (
    SELECT DISTINCT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%coronary artery bypass%'
  ),

  -- Identify the patient cohort: males aged 45-55.
  patient_cohort AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 45 AND 55
  ),

  -- Create a table of all recorded CABG procedures, including the icd_code.
  all_cabg_procedures AS (
    SELECT
      proc.subject_id,
      proc.icd_code
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      cabg_codes AS cbg
      ON proc.icd_code = cbg.icd_code AND proc.icd_version = cbg.icd_version
  ),

  -- Count the number of distinct CABG procedures for each patient in the cohort.
  -- This includes patients with zero procedures due to the LEFT JOIN.
  patient_cabg_counts AS (
    SELECT
      p.subject_id,
      COUNT(DISTINCT cbg_proc.icd_code) AS num_cabg_procedures
    FROM
      patient_cohort AS p
    LEFT JOIN
      all_cabg_procedures AS cbg_proc
      ON p.subject_id = cbg_proc.subject_id
    GROUP BY
      p.subject_id
  )

-- Calculate the 25th percentile of distinct procedure counts across the entire cohort.
SELECT DISTINCT
  PERCENTILE_CONT(num_cabg_procedures, 0.25) OVER() AS p25_distinct_cabg_procedures
FROM
  patient_cabg_counts;