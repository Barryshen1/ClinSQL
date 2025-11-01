WITH ecg_items AS (
  -- First, find the itemids corresponding to ECG procedures
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    linksto = 'procedureevents'
    AND (
      LOWER(label) LIKE '%ecg%'
      OR LOWER(label) LIKE '%ekg%'
      OR LOWER(label) LIKE '%electrocardiogram%'
    )
),
patient_procedure_counts AS (
  -- Next, count the number of ECG procedures for each patient in the specified cohort
  SELECT
    p.subject_id,
    -- Count the number of procedure events.
    -- The LEFT JOIN ensures patients with 0 procedures are included with a count of 0.
    COUNT(ecg_procs.itemid) AS num_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  LEFT JOIN
    (
      -- Pre-filter procedureevents to only include ECG-related items by joining with the ecg_items CTE.
      -- This subquery resolves the "IN subquery is not supported" error.
      SELECT
        proc.subject_id,
        proc.itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS proc
      INNER JOIN
        ecg_items
        ON proc.itemid = ecg_items.itemid
    ) AS ecg_procs
    ON p.subject_id = ecg_procs.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
  GROUP BY
    p.subject_id
)
-- Finally, calculate the 75th percentile of the procedure counts
SELECT
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75th_procedures
FROM
  patient_procedure_counts;