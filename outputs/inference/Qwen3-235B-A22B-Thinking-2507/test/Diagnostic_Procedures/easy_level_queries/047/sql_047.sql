WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),

icd_procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS icd_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE '0253%' OR icd_code LIKE '02H7X%')
  GROUP BY hadm_id
),

hcpcs_procedures AS (
  SELECT 
    hadm_id,
    COUNT(*) AS hcpcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN ('92960','93653','93654','93656','93657','93659','93660','93662','93663','93664')
  GROUP BY hadm_id
),

procedure_counts AS (
  SELECT 
    c.hadm_id,
    COALESCE(i.icd_count, 0) + COALESCE(h.hcpcs_count, 0) AS total_procedures
  FROM cohort c
  LEFT JOIN icd_procedures i ON c.hadm_id = i.hadm_id
  LEFT JOIN hcpcs_procedures h ON c.hadm_id = h.hadm_id
)

SELECT STDDEV(total_procedures) AS sd_procedures
FROM procedure_counts;