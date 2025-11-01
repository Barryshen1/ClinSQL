WITH patient_cohort AS (
  -- Step 1: Identify the cohort of male patients aged 86-96
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),

all_procedure_events AS (
  -- Step 2 & 3: Find all relevant procedure events from both ICD and ICU tables and union them
  -- ICD procedures
  SELECT
    proc.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
    ON proc.icd_code = d_proc.icd_code
    AND proc.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%cardioversion%' OR LOWER(d_proc.long_title) LIKE '%catheter ablation%'

  UNION ALL

  -- ICU procedureevents
  SELECT
    proc_ev.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc_ev
  WHERE
    -- 224290: Cardioversion
    -- 225464: Ablation
    proc_ev.itemid IN (224290, 225464)
),

patient_procedure_counts AS (
  -- Step 4: Count the number of procedures for each patient who had at least one
  SELECT
    subject_id,
    COUNT(*) AS num_procedures
  FROM
    all_procedure_events
  GROUP BY
    subject_id
),

final_cohort_counts AS (
  -- Step 5: Join back to the full cohort to include patients with zero procedures
  SELECT
    pc.subject_id,
    COALESCE(ppc.num_procedures, 0) AS num_procedures
  FROM
    patient_cohort AS pc
  LEFT JOIN
    patient_procedure_counts AS ppc
    ON pc.subject_id = ppc.subject_id
)

-- Step 6: Calculate the standard deviation of the procedure counts across the entire cohort
SELECT
  STDDEV(num_procedures) AS stddev_distinct_procedures
FROM
  final_cohort_counts;