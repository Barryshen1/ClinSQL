WITH admission_data AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
),

pancreatitis_admissions AS (
  SELECT 
    diag.hadm_id,
    diag.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE 
    (diag.icd_version = 9 AND diag.icd_code = '5770') 
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
),

admission_flags AS (
  SELECT 
    hadm_id,
    CASE WHEN MIN(seq_num) = 1 THEN 1 ELSE 0 END AS is_primary
  FROM pancreatitis_admissions
  GROUP BY hadm_id
),

procedure_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS num_diagnostic_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    d.category = 'R'  -- Diagnostic Radiology
    OR LOWER(d.short_description) LIKE '%diagnostic%'
    OR LOWER(d.long_description) LIKE '%diagnostic%'
  GROUP BY h.hadm_id
),

base AS (
  SELECT 
    ad.subject_id,
    ad.hadm_id,
    ad.los_days,
    af.is_primary,
    CASE 
      WHEN ad.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN ad.los_days BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group,
    COALESCE(pc.num_diagnostic_procedures, 0) AS num_diagnostic_procedures
  FROM admission_data ad
  INNER JOIN admission_flags af
    ON ad.hadm_id = af.hadm_id
  LEFT JOIN procedure_counts pc
    ON ad.hadm_id = pc.hadm_id
)

SELECT 
  los_group,
  CASE 
    WHEN is_primary = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_group,
  AVG(num_diagnostic_procedures) AS mean_diagnostic_procedures,
  MIN(num_diagnostic_procedures) AS min_diagnostic_procedures,
  MAX(num_diagnostic_procedures) AS max_diagnostic_procedures
FROM base
GROUP BY los_group, diagnosis_group
ORDER BY los_group, diagnosis_group;