WITH cohort AS (
  -- Base cohort: female, age 45-55, LOS 1-7 days, non-expired admissions
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 1 AND 7
    AND a.hospital_expire_flag = 0
),

hf_cohort AS (
  -- Add HF diagnosis classification (primary vs secondary)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.gender,
    c.anchor_age,
    c.los_days,
    CASE WHEN d.seq_num = 1 AND SUBSTR(icd.icd_code, 1, 3) = 'I50' THEN 1 ELSE 0 END AS is_primary_hf,
    CASE WHEN d.seq_num > 1 AND SUBSTR(icd.icd_code, 1, 3) = 'I50' THEN 1 ELSE 0 END AS has_secondary_hf
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON c.hadm_id = d.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  -- Include only admissions with at least one HF diagnosis (primary or secondary)
  QUALIFY LOGICAL_OR(is_primary_hf = 1 OR has_secondary_hf = 1)
),

imaging_counts AS (
  -- Count CT and MRI per hadm_id using HCPCS
  SELECT 
    hc.hadm_id,
    -- CT: HCPCS starting with '7' (common CT range)
    COUNTIF(SUBSTR(hc.hcpcs_cd, 1, 1) = '7') AS ct_count,
    -- MRI: HCPCS starting with '7' and description contains 'MRI'
    COUNTIF(
      SUBSTR(hc.hcpcs_cd, 1, 1) = '7' 
      AND LOWER(dh.short_description) LIKE '%mri%'
    ) AS mri_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
  ON hc.hcpcs_cd = dh.code
  GROUP BY hadm_id
),

stratified_stats AS (
  -- Join imaging to cohort and stratify by primary/secondary HF and LOS bin
  SELECT 
    hf.is_primary_hf,
    CASE 
      WHEN hf.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days' 
    END AS los_bin,
    COUNT(DISTINCT hf.hadm_id) AS n_admissions,
    AVG(COALESCE(img.ct_count, 0)) AS mean_ct_per_adm,
    MIN(COALESCE(img.ct_count, 0)) AS min_ct_per_adm,
    MAX(COALESCE(img.ct_count, 0)) AS max_ct_per_adm,
    AVG(COALESCE(img.mri_count, 0)) AS mean_mri_per_adm,
    MIN(COALESCE(img.mri_count, 0)) AS min_mri_per_adm,
    MAX(COALESCE(img.mri_count, 0)) AS max_mri_per_adm
  FROM 
    hf_cohort hf
  LEFT JOIN 
    imaging_counts img
  ON hf.hadm_id = img.hadm_id
  -- Only include admissions with primary HF or secondary HF
  WHERE 
    hf.is_primary_hf = 1 OR hf.has_secondary_hf = 1
  GROUP BY 
    hf.is_primary_hf, los_bin
)

SELECT 
  CASE WHEN is_primary_hf = 1 THEN 'Primary HF' ELSE 'Secondary HF' END AS diagnosis_type,
  los_bin,
  n_admissions,
  ROUND(mean_ct_per_adm, 2) AS mean_ct,
  min_ct_per_adm AS min_ct,
  max_ct_per_adm AS max_ct,
  ROUND(mean_mri_per_adm, 2) AS mean_mri,
  min_mri_per_adm AS min_mri,
  max_mri_per_adm AS max_mri
FROM 
  stratified_stats
ORDER BY 
  diagnosis_type, 
  CASE WHEN los_bin = '1-3 days' THEN 1 ELSE 2 END;