WITH patient_cohort AS (
  -- Step 1: Define the patient population of interest: males aged 51-61.
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
), ecg_itemids AS (
  -- Step 2: Identify itemids for ECG/telemetry procedures from the dictionary.
  -- We filter on `procedureevents` to ensure these are procedural items.
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    linksto = 'procedureevents'
    AND (
      LOWER(label) LIKE '%ecg%'
      OR LOWER(label) LIKE '%ekg%'
      OR LOWER(label) LIKE '%telemetry%'
    )
), procedure_counts_per_patient AS (
  -- Step 3: Count the number of distinct ECG/Telemetry procedures for each patient in the cohort.
  SELECT
    proc.subject_id,
    COUNT(DISTINCT proc.itemid) AS num_distinct_procedures
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc
  INNER JOIN
    patient_cohort AS cohort
    ON proc.subject_id = cohort.subject_id
  INNER JOIN
    ecg_itemids AS items
    ON proc.itemid = items.itemid
  GROUP BY
    proc.subject_id
)
-- Step 4: Calculate the 25th percentile of the procedure counts.
SELECT
  APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(25)] AS p25_distinct_procedures
FROM
  procedure_counts_per_patient;