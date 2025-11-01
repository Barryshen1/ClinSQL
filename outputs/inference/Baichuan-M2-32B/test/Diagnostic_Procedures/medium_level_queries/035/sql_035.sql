WITH patients_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,  -- Moved to patients table
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_approx
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'  -- Changed to patients table
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
),
aki_diagnoses AS (
  SELECT 
    hadm_id,
    icd_code,
    seq_num,
    CASE WHEN icd_code LIKE 'N17%' THEN 1 ELSE 0 END AS is_AKI
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
),
admissions_aki AS (
  SELECT 
    pa.hadm_id,
    pa.subject_id,
    pa.admittime,
    pa.dischtime,
    pa.age_approx,
    DATEDIFF(pa.dischtime, pa.admittime) AS los_days,
    MAX(CASE WHEN d.seq_num = 1 AND d.is_AKI = 1 THEN 1 ELSE 0 END) AS has_primary_AKI,
    MAX(CASE WHEN d.is_AKI = 1 THEN 1 ELSE 0 END) AS has_any_AKI
  FROM patients_admissions pa
  LEFT JOIN aki_diagnoses d 
    ON pa.hadm_id = d.hadm_id
  GROUP BY pa.hadm_id, pa.subject_id, pa.admittime, pa.dischtime, pa.age_approx
),
admissions_aki_filtered AS (
  SELECT 
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    age_approx,
    los_days,
    CASE 
      WHEN has_primary_AKI = 1 THEN 'primary'
      WHEN has_any_AKI = 1 THEN 'secondary'
      ELSE NULL 
    END AS aki_type
  FROM admissions_aki
  WHERE has_any_AKI = 1
),
mri_ct_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.long_description) LIKE '%magnetic resonance%'
     OR LOWER(d.long_description) LIKE '%computed tomography%'
     OR LOWER(d.long_description) LIKE '%ct scan%'
     OR LOWER(d.long_description) LIKE '%mr scan%'
  GROUP BY h.hadm_id
),
final AS (
  SELECT 
    aki.aki_type,
    CASE 
      WHEN aki.los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
      WHEN aki.los_days BETWEEN 5 AND 7 THEN 'LOS 5-7 days'
      ELSE 'Other' 
    END AS los_group,
    COUNT(DISTINCT aki.subject_id) AS patient_count,
    AVG(COALESCE(mri_ct.mri_ct_count, 0)) AS mean_mri_ct_per_admission
  FROM admissions_aki_filtered aki
  LEFT JOIN mri_ct_counts mri_ct 
    ON aki.hadm_id = mri_ct.hadm_id
  WHERE aki.los_days BETWEEN 1 AND 7
  GROUP BY aki.aki_type, los_group
  HAVING los_group IN ('LOS 1-4 days', 'LOS 5-7 days')
)

SELECT * FROM final
ORDER BY aki_type, los_group;