WITH
  -- Step 1: Identify all ICD codes related to Coronary Artery Bypass Grafting (CABG)
  cabg_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%coronary artery bypass%'
  ),

  -- Step 2: Identify distinct hospital admissions (hadm_id) that included a CABG procedure
  cabg_admissions AS (
    SELECT DISTINCT
      proc.subject_id,
      proc.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      cabg_codes
      ON proc.icd_code = cabg_codes.icd_code AND proc.icd_version = cabg_codes.icd_version
  ),

  -- Step 3: Count the number of distinct CABG admissions for each female patient aged 41-51
  patient_cabg_counts AS (
    SELECT
      p.subject_id,
      -- Count the number of CABG admissions. The LEFT JOIN ensures this will be 0 for patients with no CABG.
      COUNT(ca.hadm_id) AS num_cabg_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    LEFT JOIN
      cabg_admissions AS ca
      ON p.subject_id = ca.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 41 AND 51
    GROUP BY
      p.subject_id
  )

-- Step 4: Calculate the sample standard deviation of the number of CABG procedures per patient
SELECT
  STDDEV_SAMP(num_cabg_procedures) AS stddev_cabg_procedures_per_patient
FROM
  patient_cabg_counts;