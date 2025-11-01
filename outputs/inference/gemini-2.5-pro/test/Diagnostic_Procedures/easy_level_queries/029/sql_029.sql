WITH
  -- Step 1: Define the patient cohort: males aged 78-88
  patient_cohort AS (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
      gender = 'M'
      AND anchor_age BETWEEN 78 AND 88
  ),

  -- Step 2: Identify all pacemaker/ICD procedures by searching procedure descriptions
  pacemaker_procedures AS (
    SELECT
      proc.subject_id,
      proc.icd_code
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
      -- Find procedures related to pacemakers or implantable cardioverter-defibrillators (ICDs)
      LOWER(d_proc.long_title) LIKE '%pacemaker%'
      OR LOWER(d_proc.long_title) LIKE '%cardioverter-defibrillator%'
  ),

  -- Step 3: Count the number of distinct procedures for each patient in the cohort.
  -- A LEFT JOIN ensures we include patients with 0 procedures.
  patient_procedure_counts AS (
    SELECT
      p.subject_id,
      COUNT(DISTINCT pp.icd_code) AS num_distinct_procedures
    FROM
      patient_cohort AS p
    LEFT JOIN
      pacemaker_procedures AS pp
      ON p.subject_id = pp.subject_id
    GROUP BY
      p.subject_id
  )

-- Step 4: Calculate the 25th percentile of the distinct procedure counts
SELECT
  APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(25)] AS p25_distinct_procedures
FROM
  patient_procedure_counts;