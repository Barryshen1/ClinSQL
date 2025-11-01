WITH
-- Get male patients aged 84-94 along with their hadm_id
target_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- Identify echocardiography procedures (assuming itemid or description contains 'echo')
echo_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    pe.itemid,
    pe.value AS procedure_description
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pe.subject_id = icu.subject_id AND pe.hadm_id = icu.hadm_id
  JOIN
    target_patients p
    ON pe.subject_id = p.subject_id AND pe.hadm_id = p.hadm_id
  WHERE
    -- Filter for echocardiography procedures (adjust itemid or description as needed)
    (pe.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%echo%' OR label LIKE '%echocardiography%')
     OR LOWER(SAFE_CAST(pe.value AS STRING)) LIKE '%echo%'
     OR LOWER(SAFE_CAST(pe.value AS STRING)) LIKE '%echocardiography%')
),

-- Count distinct echocardiography procedures per patient
patient_procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT itemid) AS distinct_echo_procedures
  FROM
    echo_procedures
  GROUP BY
    subject_id
)

-- Get the maximum number of distinct echocardiography procedures
SELECT
  MAX(distinct_echo_procedures) AS max_distinct_echo_procedures
FROM
  patient_procedure_counts;