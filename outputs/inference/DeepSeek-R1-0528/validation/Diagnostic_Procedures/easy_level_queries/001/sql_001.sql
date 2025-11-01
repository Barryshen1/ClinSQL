WITH base_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
cardiac_procedures AS (
  SELECT 
    pr.hadm_id, 
    pr.icd_code, 
    pr.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%cardiac%'
    OR LOWER(d.long_title) LIKE '%heart%'
    OR LOWER(d.long_title) LIKE '%coronary%'
    OR LOWER(d.long_title) LIKE '%valve%'
    OR LOWER(d.long_title) LIKE '%aortic%'
    OR LOWER(d.long_title) LIKE '%ventricular%'
),
procedure_counts AS (
  SELECT 
    ba.hadm_id,
    COUNT(DISTINCT CONCAT(cp.icd_code, '|', cp.icd_version)) AS proc_count
  FROM base_admissions ba
  LEFT JOIN cardiac_procedures cp
    ON ba.hadm_id = cp.hadm_id
  GROUP BY ba.hadm_id
)
SELECT 
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_cardiac_procedures
FROM procedure_counts;