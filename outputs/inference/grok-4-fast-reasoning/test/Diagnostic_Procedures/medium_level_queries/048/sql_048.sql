WITH diagnosis_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN seq_num = 1 
             AND ((icd_version = 10 AND icd_code LIKE 'I50%') 
                  OR (icd_version = 9 AND icd_code LIKE '428%')) 
             THEN 1 ELSE 0 END) AS primary_hf,
    MAX(CASE WHEN (icd_version = 10 AND icd_code LIKE 'I50%') 
             OR (icd_version = 9 AND icd_code LIKE '428%') 
             THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
imaging_counts AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS num_mri_ct
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%mri%' 
     OR LOWER(dip.long_title) LIKE '%magnetic resonance%' 
     OR LOWER(dip.long_title) LIKE '%ct%' 
     OR LOWER(dip.long_title) LIKE '%computed tomography%'
  GROUP BY pi.hadm_id
)
SELECT 
  hf_type,
  los_group,
  COUNT(*) AS admission_count,
  ROUND(AVG(num_mri_ct), 2) AS mean_mri_ct_per_admission
FROM (
  SELECT 
    a.hadm_id,
    CASE WHEN df.primary_hf = 1 THEN 'Primary HF' ELSE 'Secondary HF' END AS hf_type,
    CASE WHEN los <= 3 THEN '1-3 days'
         WHEN los >= 4 AND los <= 7 THEN '4-7 days'
         ELSE NULL END AS los_group,
    COALESCE(ic.num_mri_ct, 0) AS num_mri_ct,
    los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN diagnosis_flags df 
    ON a.hadm_id = df.hadm_id
  LEFT JOIN imaging_counts ic 
    ON a.hadm_id = ic.hadm_id
  CROSS JOIN UNNEST([DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY)]) AS los
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND df.has_hf = 1
    AND a.dischtime > a.admittime  -- Ensure valid LOS
) sub
WHERE los_group IS NOT NULL
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;