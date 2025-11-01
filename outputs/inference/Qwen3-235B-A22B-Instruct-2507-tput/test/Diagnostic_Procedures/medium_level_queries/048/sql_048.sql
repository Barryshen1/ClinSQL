WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
),
hf_diagnoses AS (
  SELECT
    di.hadm_id,
    MIN(di.seq_num) AS min_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
  GROUP BY di.hadm_id
),
admissions_with_hf AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    CASE 
      WHEN hf.min_seq_num = 1 THEN 'primary'
      WHEN hf.min_seq_num > 1 THEN 'secondary'
    END AS hf_role
  FROM patient_admissions pa
  JOIN hf_diagnoses hf ON pa.hadm_id = hf.hadm_id
  WHERE pa.los_days BETWEEN 1 AND 7
),
imaging_procs AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%mri%'
     OR LOWER(d.short_description) LIKE '%ct%'
  GROUP BY h.hadm_id
),
admissions_imaging AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.hf_role,
    COALESCE(i.mri_ct_count, 0) AS mri_ct_count
  FROM admissions_with_hf a
  LEFT JOIN imaging_procs i ON a.hadm_id = i.hadm_id
),
los_groups AS (
  SELECT
    hadm_id,
    hf_role,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    mri_ct_count
  FROM admissions_imaging
  WHERE los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  hf_role,
  COUNT(*) AS admission_count,
  AVG(mri_ct_count) AS mean_mri_ct_per_admission
FROM los_groups
GROUP BY los_group, hf_role
ORDER BY los_group, hf_role;