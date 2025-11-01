WITH male_80_90 AS (
  -- Filter male patients aged 80-90
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 80 AND 90
),

admissions_with_patients AS (
  -- Join patients with admissions
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_80_90 p ON a.subject_id = p.subject_id
),

mechanical_circulatory_support AS (
  -- Identify mechanical circulatory support procedures
  SELECT DISTINCT
    pe.subject_id,
    pe.hadm_id,
    di.label AS procedure_name
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE
    -- Filter for mechanical circulatory support procedures (e.g., IABP, ECMO, Impella)
    -- Adjust this condition based on actual itemids or labels in the data
    di.label LIKE '%IABP%'
    OR di.label LIKE '%ECMO%'
    OR di.label LIKE '%Impella%'
    OR di.label LIKE '%VAD%'
    OR di.label LIKE '%LVAD%'
    OR di.label LIKE '%RVAD%'
),

procedure_counts AS (
  -- Count distinct procedures per patient
  SELECT
    subject_id,
    COUNT(DISTINCT procedure_name) AS num_procedures
  FROM
    mechanical_circulatory_support
  GROUP BY
    subject_id
)

-- Find the maximum number of distinct procedures per patient
SELECT
  MAX(num_procedures) AS max_distinct_procedures_per_patient
FROM
  procedure_counts;