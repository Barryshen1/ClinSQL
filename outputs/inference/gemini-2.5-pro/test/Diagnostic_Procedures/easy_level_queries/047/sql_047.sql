WITH
  -- Step 1 & 2: Identify all hospital admissions for the patient cohort (males aged 37-47).
  CohortAdmissions AS (
    SELECT
      adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 37 AND 47
  ),

  -- Step 3: Identify all occurrences of the relevant procedures (cardioversion or catheter ablation).
  RelevantProcedures AS (
    SELECT
      proc.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
      LOWER(d_proc.long_title) LIKE '%cardioversion%'
      OR LOWER(d_proc.long_title) LIKE '%catheter ablation%'
  ),

  -- Step 4: Count the number of relevant procedures for each hospitalization in the cohort.
  -- A LEFT JOIN ensures that admissions with zero procedures are included with a count of 0.
  ProcedureCounts AS (
    SELECT
      ca.hadm_id,
      COUNT(rp.hadm_id) AS num_procedures
    FROM CohortAdmissions AS ca
    LEFT JOIN RelevantProcedures AS rp
      ON ca.hadm_id = rp.hadm_id
    GROUP BY
      ca.hadm_id
  )

-- Step 5: Calculate the standard deviation of the procedure counts across all hospitalizations.
SELECT
  STDDEV(p.num_procedures) AS stddev_procedures_per_admission
FROM ProcedureCounts AS p;