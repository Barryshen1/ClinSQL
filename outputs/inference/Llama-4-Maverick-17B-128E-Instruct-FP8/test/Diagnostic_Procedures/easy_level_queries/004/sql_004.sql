WITH 
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 41 AND 51
),
cabg_procedures_icd AS (
  SELECT subject_id, COUNT(DISTINCT icd_code) as num_procedures_icd
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '36.1%') 
     OR (icd_version = 10 AND icd_code LIKE '021%')  
  GROUP BY subject_id
),
cabg_procedures_hcpcs AS (
  SELECT subject_id, COUNT(DISTINCT hcpcs_cd) as num_procedures_hcpcs
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd BETWEEN '33510' AND '33536'  
  GROUP BY subject_id
),
cabg_counts AS (
  SELECT 
    COALESCE(p.subject_id, h.subject_id) as subject_id,
    COALESCE(p.num_procedures_icd, 0) + COALESCE(h.num_procedures_hcpcs, 0) as total_cabg_procedures
  FROM cabg_procedures_icd p
  FULL OUTER JOIN cabg_procedures_hcpcs h ON p.subject_id = h.subject_id
  WHERE COALESCE(p.subject_id, h.subject_id) IN (SELECT subject_id FROM eligible_patients)
)
SELECT 
  STDDEV(total_cabg_procedures) as stddev_cabg_procedures
FROM cabg_counts;