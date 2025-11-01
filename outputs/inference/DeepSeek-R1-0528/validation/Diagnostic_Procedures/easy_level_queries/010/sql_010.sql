WITH base AS (
  SELECT 
    pat.subject_id, 
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  WHERE 
    pat.gender = 'M' 
    AND pat.anchor_age BETWEEN 84 AND 94
),
echo_events AS (
  -- ICD procedures for echocardiography
  SELECT 
    p.subject_id, 
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%echocardiogram%' 
    OR LOWER(d.long_title) LIKE '%echocardiography%'
  
  UNION ALL
  
  -- HCPCS events for echocardiography
  SELECT 
    h.subject_id, 
    h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%echocardiogram%' 
    OR LOWER(d.long_description) LIKE '%echocardiography%'
    OR LOWER(d.short_description) LIKE '%echocardiogram%' 
    OR LOWER(d.short_description) LIKE '%echocardiography%'
),
per_hadm_echo_count AS (
  SELECT 
    b.subject_id, 
    b.hadm_id, 
    COUNT(e.subject_id) AS num_echo
  FROM base b
  LEFT JOIN echo_events e
    ON b.subject_id = e.subject_id AND b.hadm_id = e.hadm_id
  GROUP BY b.subject_id, b.hadm_id
),
per_patient_max AS (
  SELECT 
    subject_id, 
    MAX(num_echo) AS max_echo_per_patient
  FROM per_hadm_echo_count
  GROUP BY subject_id
)
SELECT 
  MAX(max_echo_per_patient) AS max_echo_count
FROM per_patient_max;