WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),
procedure_codes AS (
  SELECT subject_id, CAST(hcpcs_cd AS STRING) AS code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON hc.hcpcs_cd = dh.code
  WHERE LOWER(dh.long_description) LIKE '%ecg%' OR LOWER(dh.long_description) LIKE '%telemetry%'
  
  UNION ALL
  
  SELECT subject_id, pi.icd_code AS code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ecg%' OR LOWER(dip.long_title) LIKE '%telemetry%'
  
  UNION ALL
  
  SELECT subject_id, CAST(pe.itemid AS STRING) AS code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%telemetry%'
),
patient_code_counts AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT pc.code) AS code_count
  FROM patients_filtered p
  LEFT JOIN procedure_codes pc ON p.subject_id = pc.subject_id
  GROUP BY p.subject_id
)
SELECT STDDEV(code_count) AS sd
FROM patient_code_counts;