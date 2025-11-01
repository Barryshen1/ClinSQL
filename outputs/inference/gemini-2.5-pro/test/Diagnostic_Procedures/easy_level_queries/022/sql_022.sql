WITH ProceduresPerHospitalization AS (
  -- Step 3: For each relevant hospitalization, count the number of distinct pacemaker/ICD procedures
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_distinct_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  -- Step 1: Link patients to their hospital admissions
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  -- Link admissions to the procedures they received
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON adm.hadm_id = proc.hadm_id
  -- Step 2: Filter for specific pacemaker or ICD procedures by joining with a subquery
  INNER JOIN (
    SELECT DISTINCT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      -- Identify procedures related to pacemakers or cardioverter-defibrillators
      LOWER(long_title) LIKE '%pacemaker%'
      OR LOWER(long_title) LIKE '%cardioverter-defibrillator%'
  ) AS RelevantProcs
    ON proc.icd_code = RelevantProcs.icd_code AND proc.icd_version = RelevantProcs.icd_version
  WHERE
    -- Step 1: Filter for the specified patient cohort (male, aged 82-92)
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
  -- Step 4: Group by hospitalization to count procedures for each one
  GROUP BY
    adm.hadm_id
)
-- Step 5: Find the minimum count across all hospitalizations that had at least one such procedure
SELECT
  MIN(num_distinct_procedures) AS min_distinct_procedures_per_hospitalization
FROM
  ProceduresPerHospitalization;