WITH patient_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
hf_diag AS (
  SELECT 
    hadm_id, 
    seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
hf_admissions AS (
  SELECT 
    hadm_id,
    MIN(seq_num) AS min_seq
  FROM hf_diag
  GROUP BY hadm_id
),
hf_types AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN min_seq = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type
  FROM hf_admissions
),
mri_ct_events AS (
  -- ICD procedures (MRI/CT)
  SELECT 
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  WHERE 
    REGEXP_CONTAINS(d.long_title, r'(?i)MRI|CT')

  UNION ALL

  -- HCPCS procedures (MRI/CT)
  SELECT 
    h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
    ON h.hcpcs_cd = dh.code
  WHERE 
    REGEXP_CONTAINS(dh.long_description, r'(?i)MRI|CT') OR
    REGEXP_CONTAINS(dh.short_description, r'(?i)MRI|CT')
),
mri_ct_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS mri_ct_count
  FROM mri_ct_events
  GROUP BY hadm_id
),
base AS (
  SELECT 
    pa.hadm_id,
    pa.age_admission,
    ht.hf_type,
    DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    COALESCE(mc.mri_ct_count, 0) AS mri_ct_count
  FROM patient_admissions pa
  INNER JOIN hf_types ht 
    ON pa.hadm_id = ht.hadm_id
  LEFT JOIN mri_ct_counts mc 
    ON pa.hadm_id = mc.hadm_id
  WHERE 
    pa.age_admission BETWEEN 90 AND 100
),
los_groups AS (
  SELECT 
    hadm_id,
    hf_type,
    mri_ct_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM base
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  hf_type,
  los_group,
  COUNT(hadm_id) AS admission_count,
  AVG(mri_ct_count) AS mean_mri_ct_per_admission
FROM los_groups
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;