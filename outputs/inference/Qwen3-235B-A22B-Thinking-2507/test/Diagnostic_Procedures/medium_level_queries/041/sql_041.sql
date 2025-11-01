WITH pancreatitis_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Determine if primary or secondary
    CASE 
      WHEN MIN(d.seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 51 AND 61
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'K85%')  -- Fixed: ICD-10 codes stored without decimals (e.g., 'K850')
      OR 
      (d.icd_version = 9 AND d.icd_code = '5770')
    )
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, p.anchor_age, p.anchor_year
),

-- Calculate LOS and filter for the required LOS groups
los_groups AS (
  SELECT 
    hadm_id,
    subject_id,
    diagnosis_type,
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1 AS los_days
  FROM pancreatitis_admissions
  WHERE 
    (DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) + 1) BETWEEN 1 AND 7
),

-- Count radiography/CT procedures per admission (fixed ILIKE to LOWER/LIKE)
imaging_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%ct%' 
    OR LOWER(d.long_title) LIKE '%computed tomography%'
    OR LOWER(d.long_title) LIKE '%radiograph%'
    OR LOWER(d.long_title) LIKE '%x-ray%'
  GROUP BY p.hadm_id
)

-- Final result with stratification
SELECT
  lg.diagnosis_type,
  CASE 
    WHEN lg.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN lg.los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  COUNT(DISTINCT lg.subject_id) AS patient_count,
  COUNT(lg.hadm_id) AS admission_count,
  AVG(COALESCE(ip.imaging_count, 0)) AS mean_imaging_per_admission
FROM los_groups lg
LEFT JOIN imaging_procedures ip ON lg.hadm_id = ip.hadm_id
GROUP BY lg.diagnosis_type, los_group
ORDER BY lg.diagnosis_type, los_group;