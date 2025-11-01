WITH heart_failure_admissions AS (
  SELECT 
    ad.hadm_id,
    ad.subject_id,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = diag.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code 
    AND diag.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND diag.seq_num = 1
    AND LOWER(d_icd.long_title) LIKE '%heart failure%'
    AND ad.dischtime > ad.admittime  -- Ensure valid LOS
),
icu_flag AS (
  SELECT 
    hfa.*,
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM 
    heart_failure_admissions hfa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON hfa.subject_id = icu.subject_id 
    AND hfa.hadm_id = icu.hadm_id
),
los_strata AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'Other'
    END AS los_bucket
  FROM 
    icu_flag
),
imaging_counts AS (
  SELECT 
    proc.hadm_id,
    COUNT(proc.seq_num) AS imaging_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code 
    AND proc.icd_version = d_proc.icd_version
  WHERE 
    LOWER(d_proc.long_title) LIKE '%ct%' 
    OR LOWER(d_proc.long_title) LIKE '%computed tomography%' 
    OR LOWER(d_proc.long_title) LIKE '%mri%' 
    OR LOWER(d_proc.long_title) LIKE '%magnetic resonance%'
  GROUP BY 
    proc.hadm_id
)
SELECT 
  ls.los_bucket,
  ls.has_icu,
  COUNT(DISTINCT ls.hadm_id) AS admission_count,
  AVG(COALESCE(im.imaging_count, 0)) AS mean_imaging_per_admission
FROM 
  los_strata ls
LEFT JOIN 
  imaging_counts im
  ON ls.hadm_id = im.hadm_id
WHERE 
  ls.los_bucket != 'Other'
GROUP BY 
  ls.los_bucket, 
  ls.has_icu
ORDER BY 
  ls.los_bucket, 
  ls.has_icu;