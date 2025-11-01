WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate LOS in days
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Check if patient had ICU stay
    CASE WHEN icu.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_used,
    -- Count CT/MRI procedures
    COUNT(DISTINCT proc.icd_code) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  -- Filter for primary heart failure (ICD-10 codes)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
  -- Check for ICU stay
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  -- Count CT/MRI procedures (using ICD-10 procedure codes)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND diag.seq_num = 1
    AND diag.icd_code LIKE 'I50%'  -- Heart failure ICD-10 codes
    AND (dproc.long_title LIKE '%computed tomography%' 
         OR dproc.long_title LIKE '%magnetic resonance%'
         OR dproc.icd_code LIKE 'BW2%'  -- CT codes
         OR dproc.icd_code LIKE 'BR3%'  -- MRI codes
        )
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, icu_used
),
los_groups AS (
  SELECT 
    hadm_id,
    icu_used,
    ct_mri_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE 'Other' 
    END AS los_group
  FROM cohort
  WHERE los_days BETWEEN 1 AND 7  -- Filter to relevant LOS
)
SELECT 
  los_group,
  icu_used,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM los_groups
GROUP BY los_group, icu_used
ORDER BY los_group, icu_used;