WITH hf_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    di.seq_num,
    CASE 
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p 
    ON a.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di 
    ON a.hadm_id = di.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic 
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dic.long_title) LIKE '%heart failure%'
    AND EXTRACT(DAY FROM (a.dischtime - a.admittime)) BETWEEN 1 AND 7
),
ct_mri_procedures AS (
  SELECT 
    ie.stay_id,
    ie.itemid
  FROM 
    physionet-data.mimiciv_3_1_icu.procedureevents ie
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d 
    ON ie.itemid = d.itemid
  WHERE 
    LOWER(d.label) LIKE '%ct%' 
    OR LOWER(d.label) LIKE '%mri%'
),
ct_mri_counts_per_admission AS (
  SELECT 
    ha.hadm_id,
    ha.diagnosis_type,
    CASE 
      WHEN ha.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN ha.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_bin,
    COUNT(cmp.itemid) AS ct_mri_count
  FROM 
    hf_admissions ha
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays icu 
    ON ha.hadm_id = icu.hadm_id
  LEFT JOIN 
    ct_mri_procedures cmp 
    ON icu.stay_id = cmp.stay_id
  GROUP BY 
    ha.hadm_id, ha.diagnosis_type, ha.los_days
)
SELECT 
  diagnosis_type,
  los_bin,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission,
  MIN(ct_mri_count) AS min_ct_mri_per_admission,
  MAX(ct_mri_count) AS max_ct_mri_per_admission
FROM 
  ct_mri_counts_per_admission
WHERE 
  los_bin IS NOT NULL
GROUP BY 
  diagnosis_type, los_bin
ORDER BY 
  diagnosis_type, los_bin;