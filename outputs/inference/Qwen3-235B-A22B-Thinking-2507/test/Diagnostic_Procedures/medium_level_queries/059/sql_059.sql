WITH patients_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 67 AND 77
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
filtered_admissions AS (
  SELECT *
  FROM patients_cohort
  WHERE los_days BETWEEN 1 AND 7
),
hf_admissions AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'I50%') 
              OR (icd_version = 9 AND icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN seq_num = 1 
              AND ((icd_version = 10 AND icd_code LIKE 'I50%') 
                   OR (icd_version = 9 AND icd_code LIKE '428%')) THEN 1 ELSE 0 END) AS is_primary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
hf_filtered AS (
  SELECT 
    f.hadm_id,
    f.los_days,
    CASE WHEN hf.is_primary = 1 THEN 'primary' ELSE 'secondary' END AS hf_type
  FROM filtered_admissions f
  INNER JOIN hf_admissions hf
    ON f.hadm_id = hf.hadm_id
  WHERE hf.has_hf = 1
),
imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%radiology%' 
    OR LOWER(d.long_description) LIKE '%x-ray%'
    OR LOWER(d.long_description) LIKE '%echo%'
    OR LOWER(d.long_description) LIKE '%ultrasound%'
    OR LOWER(d.long_description) LIKE '%mri%'
    OR LOWER(d.long_description) LIKE '%ct%'
    OR LOWER(d.long_description) LIKE '%nuclear%'
    OR LOWER(d.long_description) LIKE '%pet%'
    OR LOWER(d.long_description) LIKE '%fluoroscopy%'
    OR LOWER(d.long_description) LIKE '%angiography%'
    OR LOWER(d.long_description) LIKE '%imaging%'
  GROUP BY h.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4' 
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7' 
  END AS los_group,
  hf_type,
  APPROX_QUANTILES(COALESCE(imaging_count, 0), 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(COALESCE(imaging_count, 0), 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(COALESCE(imaging_count, 0), 100)[OFFSET(75)] AS p75
FROM hf_filtered
LEFT JOIN imaging_counts 
  USING (hadm_id)
GROUP BY los_group, hf_type
ORDER BY los_group, hf_type;