WITH cohort AS (
  -- Male patients aged 42-52 (anchor_age is provided in patients)
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 42 AND 52
),

valve_procedures AS (
  -- Procedures that mention valve AND indicate repair/replacement (common keywords)
  SELECT
    p.subject_id,
    p.icd_code,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
   AND p.icd_version = d.icd_version
  JOIN cohort c
    ON p.subject_id = c.subject_id
  WHERE LOWER(d.long_title) LIKE '%valve%'
    AND (
      LOWER(d.long_title) LIKE '%repair%'
      OR LOWER(d.long_title) LIKE '%replace%'
      OR LOWER(d.long_title) LIKE '%replacement%'
      OR LOWER(d.long_title) LIKE '%valvuloplasty%'
      OR LOWER(d.long_title) LIKE '%prosthesis%'
      OR LOWER(d.long_title) LIKE '%valvotomy%'
    )
),

per_patient_counts AS (
  -- Count distinct procedure codes per patient (distinct valve procedures)
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_valve_proc_count
  FROM valve_procedures
  GROUP BY subject_id
)

-- Final: average distinct valve procedures per patient, and cohort size for context
SELECT
  AVG(distinct_valve_proc_count) AS avg_distinct_valve_procedures_per_patient,
  COUNT(*) AS n_patients_in_cohort,
  MIN(distinct_valve_proc_count) AS min_distinct_valve_procedures_per_patient,
  MAX(distinct_valve_proc_count) AS max_distinct_valve_procedures_per_patient
FROM per_patient_counts;