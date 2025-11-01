WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- MCS from ICU procedureevents (bedside procedures)
mcs_procedureevents AS (
  SELECT subject_id, procedure_type
  FROM (
    SELECT DISTINCT p.subject_id, 
           CASE 
             WHEN i.label LIKE '%Intra-aortic balloon%' OR i.itemid IN ('225807', '225808') THEN 'IABP'
             WHEN i.label LIKE '%Ventricular assist%' OR i.itemid IN ('225916', '225917') THEN 'VAD'
             WHEN i.label LIKE '%ECMO%' OR i.itemid IN ('228351', '228353') THEN 'ECMO'
             ELSE NULL 
           END AS procedure_type
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` i ON CAST(p.itemid AS STRING) = i.itemid
    INNER JOIN patients_filtered pf ON p.subject_id = pf.subject_id
    WHERE p.starttime IS NOT NULL  -- Valid procedure events
  ) sub
  WHERE procedure_type IS NOT NULL
),

-- MCS from HOSP procedures_icd (coded procedures)
mcs_icd_procedures AS (
  SELECT subject_id, procedure_type
  FROM (
    SELECT DISTINCT pi.subject_id,
           CASE 
             WHEN pi.icd_code IN ('39.65', '37.62') THEN 'VAD'  -- Assist devices
             WHEN pi.icd_code = '39.64' THEN 'IABP'             -- Counterpump
             WHEN pi.icd_code LIKE '39.66%' THEN 'ECMO'         -- Extracorporeal
             ELSE NULL 
           END AS procedure_type
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN patients_filtered pf ON pi.subject_id = pf.subject_id
    WHERE pi.icd_version = 'ICD-9'  -- MIMIC-IV primarily ICD-9 for procedures; adjust if ICD-10 needed
  ) sub
  WHERE procedure_type IS NOT NULL
),

-- Combine sources
all_mcs AS (
  SELECT subject_id, procedure_type
  FROM mcs_procedureevents
  
  UNION ALL
  
  SELECT subject_id, procedure_type
  FROM mcs_icd_procedures
),

-- Per-patient distinct MCS count
patient_counts AS (
  SELECT subject_id, COUNT(DISTINCT procedure_type) AS count_distinct_mcs
  FROM all_mcs
  GROUP BY subject_id
  QUALIFY count_distinct_mcs >= 1  -- Only patients with MCS
)

-- Minimum across patients in cohort
SELECT COALESCE(MIN(count_distinct_mcs), 0) AS min_distinct_mcs_per_patient
FROM patient_counts;