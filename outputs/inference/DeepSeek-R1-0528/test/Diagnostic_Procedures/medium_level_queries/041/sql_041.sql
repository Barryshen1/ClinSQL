WITH proc_codes AS (
  -- Identify relevant radiography/CT procedure codes
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%radiograph%' OR 
    LOWER(long_title) LIKE '%x-ray%' OR 
    LOWER(long_title) LIKE '%computed tomography%' OR 
    LOWER(long_title) LIKE '%ct scan%'
),
base_diag AS (
  -- Get min seq_num for pancreatitis per admission
  SELECT 
    hadm_id, 
    MIN(seq_num) AS min_seq_num 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '5770') OR 
    (icd_version = 10 AND icd_code LIKE 'K85%')
  GROUP BY hadm_id
),
filtered_admissions AS (
  -- Filter admissions: males aged 51-61, LOS 1-7 days
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN diag.min_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type,
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN base_diag diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) 
        BETWEEN 51 AND 61
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
procedure_counts AS (
  -- Count radiography/CT procedures per admission
  SELECT 
    p.hadm_id,
    COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN proc_codes pc
    ON p.icd_code = pc.icd_code AND p.icd_version = pc.icd_version
  GROUP BY p.hadm_id
)
-- Final aggregation
SELECT 
  fa.los_group,
  fa.diagnosis_type,
  COUNT(DISTINCT fa.hadm_id) AS admission_count,
  AVG(COALESCE(pc.procedure_count, 0)) AS mean_procedures
FROM filtered_admissions fa
LEFT JOIN procedure_counts pc
  ON fa.hadm_id = pc.hadm_id
GROUP BY fa.los_group, fa.diagnosis_type
ORDER BY fa.los_group, fa.diagnosis_type;