WITH aki_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
        ELSE 'Other' 
    END AS los_group,
    diag.seq_num,
    CASE 
        WHEN diag.seq_num = 1 THEN 'Primary'
        ELSE 'Secondary' 
    END AS aki_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND diag.icd_code LIKE 'N17%'
    AND diag.icd_version = 10
),
procedures AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE 
    (icd_code LIKE 'BH%' OR icd_code LIKE 'BF%')
    AND icd_version = 10
  GROUP BY hadm_id
)
SELECT 
  aki.los_group,
  aki.aki_type,
  COUNT(DISTINCT aki.subject_id) AS patient_count,
  COUNT(DISTINCT aki.hadm_id) AS admission_count,
  COALESCE(AVG(proc.num_procedures), 0) AS mean_mri_ct_per_admission
FROM aki_admissions aki
LEFT JOIN procedures proc
  ON aki.hadm_id = proc.hadm_id
WHERE aki.los_group IN ('1-4', '5-7')
GROUP BY aki.los_group, aki.aki_type
ORDER BY aki.los_group, aki.aki_type;