WITH patients_51_61 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
all_procedures AS (
  SELECT p.subject_id, p.icd_code AS procedure_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%ECG%' OR d.long_title LIKE '%Telemetry%'
  
  UNION ALL
  
  SELECT pe.subject_id, CAST(pe.itemid AS STRING) AS procedure_type
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ECG%' OR di.label LIKE '%Telemetry%'
  
  UNION ALL
  
  SELECT h.subject_id, h.hcpcs_cd AS procedure_type
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE d.long_description LIKE '%ECG%' OR d.long_description LIKE '%Telemetry%'
    OR d.short_description LIKE '%ECG%' OR d.short_description LIKE '%Telemetry%'
),
patient_procedure_counts AS (
  SELECT p.subject_id, COUNT(DISTINCT ap.procedure_type) AS num_procedures
  FROM patients_51_61 p
  LEFT JOIN all_procedures ap ON p.subject_id = ap.subject_id
  GROUP BY p.subject_id
)
SELECT PERCENTILE_CONT(num_procedures, 0.25) WITHIN GROUP (ORDER BY num_procedures) AS percentile_25
FROM patient_procedure_counts;