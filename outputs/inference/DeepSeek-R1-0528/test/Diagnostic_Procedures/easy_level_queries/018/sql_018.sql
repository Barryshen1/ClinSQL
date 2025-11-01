WITH procedure_events AS (
  -- ICD procedures (catheter ablation or cardioversion)
  SELECT 
    p.subject_id, 
    p.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%catheter ablation%' 
    OR LOWER(d.long_title) LIKE '%cardioversion%'
  
  UNION ALL
  
  -- HCPCS procedures (catheter ablation or cardioversion)
  SELECT 
    h.subject_id, 
    h.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%catheter ablation%' 
    OR LOWER(d.long_description) LIKE '%cardioversion%'
),

cohort AS (
  -- Male patients with >=1 admission at age 86-96
  SELECT 
    pt.subject_id,
    pt.anchor_age,
    pt.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  WHERE 
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 86 AND 96
  GROUP BY pt.subject_id, pt.anchor_age, pt.anchor_year
),

counts AS (
  -- Count procedures per patient (only when age 86-96)
  SELECT 
    c.subject_id,
    COUNT(pe.subject_id) AS num_procedures
  FROM cohort c
  LEFT JOIN procedure_events pe
    ON c.subject_id = pe.subject_id
    AND (c.anchor_age + (EXTRACT(YEAR FROM pe.chartdate) - c.anchor_year)) BETWEEN 86 AND 96
  GROUP BY c.subject_id
)

-- Compute standard deviation of procedure counts
SELECT STDDEV(num_procedures) AS sd_procedures
FROM counts;