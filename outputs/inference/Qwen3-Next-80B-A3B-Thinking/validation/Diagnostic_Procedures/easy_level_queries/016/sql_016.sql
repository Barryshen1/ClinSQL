WITH filtered_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
),
ecg_procedures AS (
  SELECT hadm_id, CAST(pe.itemid AS STRING) AS proc_code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%ECG%' OR di.label LIKE '%EKG%' OR di.label LIKE '%telemetry%'
  
  UNION ALL
  
  SELECT hadm_id, pi.icd_code AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE dip.long_title LIKE '%ECG%' OR dip.long_title LIKE '%EKG%' OR dip.long_title LIKE '%telemetry%'
  
  UNION ALL
  
  SELECT hadm_id, h.hcpcs_cd AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE dh.short_description LIKE '%ECG%' OR dh.short_description LIKE '%EKG%' OR dh.short_description LIKE '%telemetry%'
),
procedure_counts AS (
  SELECT hadm_id, COUNT(DISTINCT proc_code) AS count_procedures
  FROM ecg_procedures
  GROUP BY hadm_id
)
SELECT APPROX_QUANTILES(COALESCE(pc.count_procedures, 0), 100)[OFFSET(75)] AS percentile_75
FROM filtered_admissions fa
LEFT JOIN procedure_counts pc ON fa.hadm_id = pc.hadm_id;