WITH aki_cohort AS (
  -- Identify admissions with AKI diagnoses
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag if primary AKI exists
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di 
        JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.subject_id = p.subject_id 
          AND di.hadm_id = a.hadm_id 
          AND di.seq_num = 1 
          AND (dd.icd_code LIKE 'N17%' OR dd.icd_code LIKE '584%')
      ) THEN 'Primary'
      ELSE 'Secondary'
    END AS aki_type
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL 
    AND a.dischtime IS NOT NULL
    -- Admission has at least one AKI diagnosis (primary or secondary)
    AND EXISTS (
      SELECT 1 
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di 
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
      WHERE di.subject_id = p.subject_id 
        AND di.hadm_id = a.hadm_id 
        AND (dd.icd_code LIKE 'N17%' OR dd.icd_code LIKE '584%')
    )
),

imaging_counts AS (
  -- Count distinct diagnostic imaging procedures per admission
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS num_imaging_studies,
    ac.aki_type,
    ac.los_days
  FROM 
    aki_cohort ac
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi ON ac.subject_id = pi.subject_id AND ac.hadm_id = pi.hadm_id
  LEFT JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  WHERE 
    -- Filter to diagnostic imaging (case-insensitive keyword match)
    (LOWER(dp.long_title) LIKE '%ct%' 
     OR LOWER(dp.long_title) LIKE '%mri%' 
     OR LOWER(dp.long_title) LIKE '%x-ray%' 
     OR LOWER(dp.long_title) LIKE '%ultrasound%' 
     OR LOWER(dp.long_title) LIKE '%mammography%')
  GROUP BY 
    ac.subject_id, ac.hadm_id, ac.aki_type, ac.los_days
),

los_buckets AS (
  SELECT 
    subject_id,
    hadm_id,
    num_imaging_studies,
    aki_type,
    CASE 
      WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
      WHEN los_days >= 4 AND los_days <= 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_bucket
  FROM 
    imaging_counts
  WHERE 
    los_days >= 1 AND los_days <= 7  -- Restrict to 1-7 days
)

SELECT 
  aki_type,
  los_bucket,
  COUNT(*) AS num_admissions,
  -- Median using APPROX_QUANTILES (positions: 0=0%, 1=25%, 2=50%, 3=75%)
  APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(2)] AS median_imaging,
  APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(3)] AS q3,
  -- IQR
  APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(3)] - APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(1)] AS iqr_imaging,
  -- Mean for completeness
  AVG(num_imaging_studies) AS mean_imaging
FROM 
  los_buckets
WHERE 
  los_bucket IS NOT NULL
GROUP BY 
  aki_type, 
  los_bucket
ORDER BY 
  aki_type, 
  CASE los_bucket 
    WHEN '1-3 days' THEN 1 
    WHEN '4-7 days' THEN 2 
  END;