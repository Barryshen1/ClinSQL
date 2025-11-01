WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 43 AND 53
),

ami_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
  )
),

admissions_with_ami AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag if AMI is primary diagnosis
    MAX(CASE WHEN di.seq_num = 1 AND ac.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS is_primary_ami,
    -- Flag if AMI appears anywhere
    MAX(CASE WHEN ac.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  LEFT JOIN ami_codes ac
    ON di.icd_code = ac.icd_code
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),

admissions_stratified AS (
  SELECT 
    hadm_id,
    los_days,
    CASE 
      WHEN is_primary_ami = 1 THEN 'primary'
      WHEN is_primary_ami = 0 AND has_ami = 1 THEN 'secondary'
      ELSE NULL 
    END AS ami_type
  FROM admissions_with_ami
  WHERE has_ami = 1
    AND los_days > 0 AND los_days <= 7
),

imaging_procs AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN admissions_stratified a ON h.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%xray%'
     OR LOWER(d.short_description) LIKE '%radiography%'
     OR LOWER(d.short_description) LIKE '%ct%'
     OR LOWER(d.short_description) LIKE '%computed tomography%'
     OR LOWER(d.long_description) LIKE '%xray%'
     OR LOWER(d.long_description) LIKE '%radiography%'
     OR LOWER(d.long_description) LIKE '%ct%'
     OR LOWER(d.long_description) LIKE '%computed tomography%'
  GROUP BY h.hadm_id
),

final_counts AS (
  SELECT 
    a.ami_type,
    CASE 
      WHEN a.los_days <= 3 THEN '1-3 days'
      WHEN a.los_days <= 7 THEN '4-7 days'
    END AS los_group,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM admissions_stratified a
  LEFT JOIN imaging_procs i ON a.hadm_id = i.hadm_id
)

SELECT
  ami_type,
  los_group,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(250)] AS iqr_lower,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(750)] AS iqr_upper
FROM final_counts
WHERE ami_type IS NOT NULL
GROUP BY ami_type, los_group
ORDER BY ami_type, los_group;