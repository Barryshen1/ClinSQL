WITH heart_failure_patients AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND di.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code = '428')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
admissions_with_icu AS (
  SELECT 
    hfp.hadm_id,
    hfp.los_days,
    hfp.admittime,
    hfp.dischtime,
    CASE WHEN i.stay_id IS NOT NULL THEN 'yes' ELSE 'no' END AS icu_use
  FROM heart_failure_patients hfp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON hfp.hadm_id = i.hadm_id
),
imaging_procedures AS (
  SELECT 
    hce.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hce
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON hce.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ct%'
     OR LOWER(d.short_description) LIKE '%mri%'
  GROUP BY hce.hadm_id
),
admissions_with_imaging AS (
  SELECT 
    awi.hadm_id,
    awi.los_days,
    awi.icu_use,
    COALESCE(ip.ct_mri_count, 0) AS ct_mri_count
  FROM admissions_with_icu awi
  LEFT JOIN imaging_procedures ip ON awi.hadm_id = ip.hadm_id
  WHERE awi.los_days BETWEEN 1 AND 7
),
stratified AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    icu_use,
    ct_mri_count
  FROM admissions_with_imaging
)
SELECT 
  los_group,
  icu_use,
  COUNT(*) AS admission_count,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM stratified
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;