WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),

-- HOSP: HCPCS/CPT events (short_description)
hosp_hcpcs_ecg AS (
  SELECT
    subject_id,
    CONCAT('hcpcs|', COALESCE(hcpcs_cd, '')) AS proc_code,
    COALESCE(short_description, '') AS proc_desc
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE subject_id IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(short_description, '')),
        r'(ecg|ekg|electrocardio|telemetry|telemetric|rhythm|rhythm strip|cardiac monitor|heart monitor)')
),

-- HOSP: ICD procedures (join to d_icd_procedures long_title)
hosp_icdproc_ecg AS (
  SELECT
    p.subject_id,
    CONCAT('icdproc|', p.icd_code) AS proc_code,
    COALESCE(d.long_title, '') AS proc_desc
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE p.subject_id IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(d.long_title, '')),
        r'(ecg|ekg|electrocardio|telemetry|telemetric|rhythm|rhythm strip|cardiac monitor|heart monitor)')
),

-- ICU: procedureevents (join to d_items for label)
icu_proc_ecg AS (
  SELECT
    pe.subject_id,
    CONCAT('icu_item|', CAST(pe.itemid AS STRING)) AS proc_code,
    COALESCE(di.label, CAST(pe.value AS STRING), '') AS proc_desc
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.subject_id IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(COALESCE(di.label, CAST(pe.value AS STRING), '')),
        r'(ecg|ekg|electrocardio|telemetry|telemetric|rhythm|rhythm strip|cardiac monitor|heart monitor)')
),

-- Union all candidate ECG/telemetry procedure "types" per subject, deduplicate types per subject
subject_proc_types AS (
  SELECT DISTINCT subject_id, proc_code
  FROM (
    SELECT subject_id, proc_code FROM hosp_hcpcs_ecg
    UNION ALL
    SELECT subject_id, proc_code FROM hosp_icdproc_ecg
    UNION ALL
    SELECT subject_id, proc_code FROM icu_proc_ecg
  )
  WHERE subject_id IS NOT NULL
),

-- Count distinct procedure types per subject (only for those who have at least one)
per_subject_counts AS (
  SELECT
    subject_id,
    COUNT(*) AS proc_count
  FROM subject_proc_types
  GROUP BY subject_id
),

-- Include zeros for cohort members with no matching procedures
counts_with_zeros AS (
  SELECT
    pc.subject_id,
    COALESCE(ps.proc_count, 0) AS proc_count
  FROM patients_cohort pc
  LEFT JOIN per_subject_counts ps
    ON pc.subject_id = ps.subject_id
)

-- final: compute 75th percentile (approx)
SELECT
  (SELECT quantiles[OFFSET(75)]
   FROM (
     SELECT APPROX_QUANTILES(proc_count, 100) AS quantiles
     FROM counts_with_zeros
   )
  ) AS p75_distinct_ecg_telemetry_procedures_per_patient
;