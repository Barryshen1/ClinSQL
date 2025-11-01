WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 BETWEEN 1 AND 7
),
primary_diag AS (
  SELECT 
    hadm_id,
    icd_code AS primary_icd,
    icd_version AS primary_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
),
has_ami AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND icd_code LIKE 'I21%')
),
with_ami_type AS (
  SELECT 
    ea.*,
    pd.primary_icd,
    pd.primary_version,
    CASE WHEN ha.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ami_flag,
    CASE 
      WHEN ha.hadm_id IS NOT NULL 
           AND ((pd.primary_version = 9 AND pd.primary_icd LIKE '410%') 
                OR (pd.primary_version = 10 AND pd.primary_icd LIKE 'I21%')) 
      THEN 'primary'
      WHEN ha.hadm_id IS NOT NULL THEN 'secondary'
      ELSE NULL 
    END AS ami_type,
    CASE WHEN ea.los <= 3 THEN '1-3' ELSE '4-7' END AS los_group
  FROM eligible_admissions ea
  LEFT JOIN primary_diag pd 
    ON ea.hadm_id = pd.hadm_id
  LEFT JOIN has_ami ha 
    ON ea.hadm_id = ha.hadm_id
  WHERE ha.hadm_id IS NOT NULL  -- Only AMI admissions
),
imaging_counts AS (
  SELECT 
    proc.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON proc.icd_code = dip.icd_code 
    AND proc.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%x-ray%'
     OR LOWER(dip.long_title) LIKE '%radiography%'
     OR LOWER(dip.long_title) LIKE '%ct%'
     OR LOWER(dip.long_title) LIKE '%computed tomography%'
     OR LOWER(dip.long_title) LIKE '%tomography%'
  GROUP BY proc.hadm_id
),
stats AS (
  SELECT 
    wat.los_group,
    wat.ami_type,
    COALESCE(ic.num_imaging, 0) AS num
  FROM with_ami_type wat
  LEFT JOIN imaging_counts ic 
    ON wat.hadm_id = ic.hadm_id
  WHERE wat.ami_type IN ('primary', 'secondary')
)
SELECT 
  los_group,
  ami_type,
  ANY_VALUE(median) AS median,
  ANY_VALUE(q1) AS q1,
  ANY_VALUE(q3) AS q3
FROM (
  SELECT 
    *,
    PERCENTILE_CONT(num, 0.5) OVER (PARTITION BY los_group, ami_type) AS median,
    PERCENTILE_CONT(num, 0.25) OVER (PARTITION BY los_group, ami_type) AS q1,
    PERCENTILE_CONT(num, 0.75) OVER (PARTITION BY los_group, ami_type) AS q3
  FROM stats
)
GROUP BY los_group, ami_type
ORDER BY los_group, ami_type;