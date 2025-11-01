WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate age at admission using anchor_year offset
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
ami_admissions AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS primary_ami,
    MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS secondary_ami
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '410%') OR 
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  GROUP BY hadm_id
  HAVING MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) = 1  -- Primary AMI
      OR MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) = 1  -- Secondary AMI
),
radiology_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    LOWER(long_description) LIKE '%radiograph%' OR 
    LOWER(long_description) LIKE '%x-ray%' OR 
    LOWER(long_description) LIKE '%x ray%' OR 
    LOWER(long_description) LIKE '%computed tomography%' OR 
    LOWER(long_description) LIKE '%ct scan%' OR 
    LOWER(long_description) LIKE '% ct %' OR 
    LOWER(long_description) LIKE '%cat scan%' OR 
    LOWER(long_description) LIKE '%computerized tomography%'
),
procedure_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN (SELECT code FROM radiology_codes)
  GROUP BY hadm_id
),
base AS (
  SELECT 
    c.hadm_id,
    c.age_at_admission,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE 
      WHEN a.primary_ami = 1 THEN 'Primary'
      WHEN a.secondary_ami = 1 THEN 'Secondary'
    END AS ami_type,
    COALESCE(pc.num_procedures, 0) AS num_procedures
  FROM cohort c
  INNER JOIN ami_admissions a 
    ON c.hadm_id = a.hadm_id
  LEFT JOIN procedure_counts pc 
    ON c.hadm_id = pc.hadm_id
  WHERE 
    c.age_at_admission BETWEEN 43 AND 53
    AND DATE_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 7
),
los_groups AS (
  SELECT 
    ami_type,
    num_procedures,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM base
)
SELECT 
  ami_type,
  los_group,
  quantiles[OFFSET(2)] AS median,
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(3)] AS q3,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM (
  SELECT 
    ami_type,
    los_group,
    APPROX_QUANTILES(num_procedures, 4) AS quantiles
  FROM los_groups
  GROUP BY ami_type, los_group
)
ORDER BY ami_type, los_group;