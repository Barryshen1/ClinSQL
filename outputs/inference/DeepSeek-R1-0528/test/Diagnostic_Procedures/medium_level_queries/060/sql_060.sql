WITH filtered_admissions AS (
  SELECT 
      adm.subject_id, 
      adm.hadm_id, 
      adm.admittime, 
      adm.dischtime,
      -- Calculate age at admission
      pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON adm.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
      AND adm.subject_id = diag.subject_id
  WHERE 
      pt.gender = 'M'
      AND diag.seq_num = 1  -- Primary diagnosis
      AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      )
      -- Age 49-59 at admission
      AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 49 AND 59
),
los_groups AS (
  SELECT 
      *,
      DATE_DIFF(dischtime, admittime, DAY) AS los_days,
      CASE 
          WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
          WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      END AS los_group
  FROM filtered_admissions
  -- Only include LOS 1-7 days
  WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),
ct_mri_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
      LOWER(long_title) LIKE '%computed tomography%' 
      OR LOWER(long_title) LIKE '%magnetic resonance%'
      OR LOWER(long_title) LIKE '%mri%'
      OR LOWER(long_title) LIKE '%ct%'
),
ct_mri_counts AS (
  SELECT 
      lg.hadm_id,
      COUNT(proc.icd_code) AS ct_mri_count  -- Count scans per admission
  FROM los_groups lg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      ON lg.hadm_id = proc.hadm_id
      AND lg.subject_id = proc.subject_id
  LEFT JOIN ct_mri_codes c
      ON proc.icd_code = c.icd_code
      AND proc.icd_version = c.icd_version
  GROUP BY lg.hadm_id
)
SELECT 
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
            WHERE icu.hadm_id = lg.hadm_id
        ) THEN 'Yes' 
        ELSE 'No' 
    END AS icu_use,
    lg.los_group,
    COUNT(DISTINCT lg.hadm_id) AS admission_count,
    AVG(cc.ct_mri_count) AS mean_ct_mri_per_admission
FROM los_groups lg
LEFT JOIN ct_mri_counts cc
    ON lg.hadm_id = cc.hadm_id
GROUP BY icu_use, los_group
ORDER BY icu_use, los_group;