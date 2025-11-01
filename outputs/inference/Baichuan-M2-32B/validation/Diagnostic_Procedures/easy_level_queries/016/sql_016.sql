WITH eligible_patients AS (
  SELECT 
    a.hadm_id,
    a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 75 AND 85
),
ecg_telemetry_procedures AS (
  -- ICD-9-CM procedures
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    p.icd_code AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    d.long_title LIKE '%ecg%' 
    OR d.long_title LIKE '%electrocardiogram%'
    OR d.long_title LIKE '%telemetry%'
    OR d.long_title LIKE '%monitoring%'
  UNION ALL
  -- HCPCS procedures
  SELECT 
    h.subject_id, 
    h.hadm_id, 
    h.hcpcs_cd AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE 
    d.long_description LIKE '%ecg%' 
    OR d.long_description LIKE '%electrocardiogram%'
    OR d.long_description LIKE '%telemetry%'
    OR d.long_description LIKE '%monitoring%'
),
procedures_per_hadm AS (
  SELECT 
    e.hadm_id,
    COUNT(DISTINCT et.procedure_code) AS distinct_procedures
  FROM eligible_patients e
  LEFT JOIN ecg_telemetry_procedures et 
    ON e.hadm_id = et.hadm_id
  GROUP BY e.hadm_id
)
SELECT 
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_procedures
FROM procedures_per_hadm;