WITH hf_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Determine if HF is primary (seq_num = 1) or secondary (seq_num > 1)
    MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) AS is_primary_hf,
    MAX(CASE WHEN di.seq_num > 1 THEN 1 ELSE 0 END) AS is_secondary_hf
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 45 AND 55
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND LOWER(d.long_title) LIKE '%heart failure%'
  GROUP BY a.hadm_id, p.subject_id, p.gender, age_at_admit, los_days
),
imaging_per_admission AS (
  SELECT 
    h.hadm_id,
    h.is_primary_hf,
    h.is_secondary_hf,
    h.los_days,
    COUNT(*) AS imaging_count
  FROM hf_admissions h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents hc ON h.hadm_id = hc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d ON hc.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ct%' 
     OR LOWER(d.short_description) LIKE '%mri%'
  GROUP BY h.hadm_id, h.is_primary_hf, h.is_secondary_hf, h.los_days
),
grouped_stats AS (
  SELECT
    CASE 
      WHEN is_primary_hf = 1 THEN 'Primary'
      WHEN is_secondary_hf = 1 THEN 'Secondary'
    END AS hf_diagnosis_type,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    AVG(imaging_count) AS mean_imaging_per_admission,
    MIN(imaging_count) AS min_imaging_per_admission,
    MAX(imaging_count) AS max_imaging_per_admission
  FROM imaging_per_admission
  GROUP BY hf_diagnosis_type, los_group
)
SELECT 
  hf_diagnosis_type,
  los_group,
  ROUND(mean_imaging_per_admission, 2) AS mean_ct_mri_per_admission,
  min_imaging_per_admission,
  max_imaging_per_admission
FROM grouped_stats
ORDER BY hf_diagnosis_type, los_group;