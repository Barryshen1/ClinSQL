WITH
  -- Step 1: Identify all ICD codes related to valve repair or replacement
  ValveProcedureCodes AS (
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%valve%' AND (
        LOWER(long_title) LIKE '%replacement%' OR LOWER(long_title) LIKE '%repair%'
      )
  ),

  -- Step 2: For each male patient aged 42-52 who had a valve procedure,
  -- count the number of unique valve procedures they underwent.
  PatientValveProcCounts AS (
    SELECT
      p.subject_id,
      COUNT(DISTINCT proc.icd_code) AS num_distinct_valve_procs
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON p.subject_id = proc.subject_id
    INNER JOIN
      ValveProcedureCodes AS vpc
      ON proc.icd_code = vpc.icd_code AND proc.icd_version = vpc.icd_version
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 42 AND 52
    GROUP BY
      p.subject_id
  )

-- Step 3: Calculate the average of these counts across all relevant patients.
SELECT
  AVG(num_distinct_valve_procs) AS avg_distinct_valve_procedures_per_patient
FROM
  PatientValveProcCounts;