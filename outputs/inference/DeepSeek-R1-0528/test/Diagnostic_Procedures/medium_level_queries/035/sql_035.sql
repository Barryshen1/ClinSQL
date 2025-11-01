WITH base_cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),

aki_diagnoses AS (
  SELECT 
    diag.hadm_id,
    diag.seq_num,
    diag.icd_code,
    diag.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN base_cohort bc ON diag.hadm_id = bc.hadm_id
  WHERE 
    (diag.icd_version = 9 AND diag.icd_code LIKE '584%') 
    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
),

aki_admissions AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_aki
  FROM aki_diagnoses
  GROUP BY hadm_id
),

aki_classified AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN has_primary_aki = 1 THEN 'Primary'
      ELSE 'Secondary' 
    END AS aki_type
  FROM aki_admissions
),

mri_ct_icd_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'computed tomography|ct scan|magnetic resonance|mri')
),

mri_ct_hcpcs_codes AS (
  SELECT 
    code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_description), r'computed tomography|ct scan|magnetic resonance|mri')
),

imaging_icd AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS icd_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN mri_ct_icd_codes c 
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
  INNER JOIN aki_classified aki 
    ON p.hadm_id = aki.hadm_id
  GROUP BY p.hadm_id
),

imaging_hcpcs AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS hcpcs_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN mri_ct_hcpcs_codes c 
    ON h.hcpcs_cd = c.code
  INNER JOIN aki_classified aki 
    ON h.hadm_id = aki.hadm_id
  GROUP BY h.hadm_id
),

imaging_combined AS (
  SELECT 
    aki.hadm_id,
    COALESCE(i.icd_count, 0) + COALESCE(h.hcpcs_count, 0) AS total_imaging
  FROM aki_classified aki
  LEFT JOIN imaging_icd i 
    ON aki.hadm_id = i.hadm_id
  LEFT JOIN imaging_hcpcs h 
    ON aki.hadm_id = h.hadm_id
),

final_cohort AS (
  SELECT 
    bc.hadm_id,
    bc.age_at_admission,
    bc.los_days,
    aki.aki_type,
    COALESCE(img.total_imaging, 0) AS total_events
  FROM base_cohort bc
  INNER JOIN aki_classified aki 
    ON bc.hadm_id = aki.hadm_id
  LEFT JOIN imaging_combined img 
    ON bc.hadm_id = img.hadm_id
  WHERE 
    bc.age_at_admission BETWEEN 43 AND 53
)

SELECT 
  aki_type,
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  COUNT(hadm_id) AS admission_count,
  AVG(total_events) AS mean_imaging_per_admission
FROM final_cohort
GROUP BY aki_type, los_group
ORDER BY aki_type, los_group;