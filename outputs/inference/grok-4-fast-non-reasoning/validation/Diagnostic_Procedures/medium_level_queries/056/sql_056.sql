WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) AS los_days,
    CASE 
      WHEN EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d.seq_num = 1
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'K85%') 
      OR (d.icd_version = '9' AND d.icd_code = '577.0')
    )
    AND a.hospital_expire_flag = 0
    AND EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 1 AND 8
),
ct_mri_procs AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.los_group,
    COUNT(*) AS proc_count_per_adm  -- Count procedures per admission (not DISTINCT hadm_id, as that's 1)
  FROM 
    filtered_admissions fa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON 
    fa.subject_id = pr.subject_id AND fa.hadm_id = pr.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON 
    pr.icd_code = dip.icd_code AND pr.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%ct%' 
    OR LOWER(dip.long_title) LIKE '%computed tomography%' 
    OR LOWER(dip.long_title) LIKE '%mri%' 
    OR LOWER(dip.long_title) LIKE '%magnetic resonance%'
  GROUP BY 
    fa.subject_id, fa.hadm_id, fa.los_group
),
adm_procs AS (
  SELECT 
    los_group,
    COUNT(DISTINCT hadm_id) AS patient_count,  -- Count distinct admissions (proxy for patients per group)
    AVG(proc_count_per_adm) AS mean_procs_per_admission
  FROM ct_mri_procs
  GROUP BY los_group
)
SELECT 
  los_group,
  COALESCE(patient_count, 0) AS patient_count,
  ROUND(COALESCE(mean_procs_per_admission, 0.0), 2) AS mean_ct_mri_procs_per_admission
FROM adm_procs
ORDER BY 
  CASE los_group 
    WHEN '1-4 days' THEN 1 
    ELSE 2 
  END;