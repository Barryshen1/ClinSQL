WITH hf_admissions AS (
  -- Identify admissions with HF diagnoses for men aged 67-77
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.seq_num,
    -- LOS in days (inclusive)
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hospital_expire_flag = 0
    AND d.icd_version = 10  -- Focus on ICD-10 (common in MIMIC-IV v3.1)
    AND d.icd_code LIKE 'I50%'  -- Heart failure codes
    AND (DATE_DIFF(a.dischtime, a.admittime, DAY) + 1) BETWEEN 1 AND 7  -- LOS 1-7 days
),
imaging_counts AS (
  -- Count imaging procedures per admission (proxy for imaging studies)
  SELECT 
    ha.hadm_id,
    -- LOS stratum
    CASE 
      WHEN ha.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      ELSE '5-7 days'
    END AS los_stratum,
    -- HF type
    CASE 
      WHEN ha.seq_num = 1 THEN 'Primary HF'
      ELSE 'Secondary HF'
    END AS hf_type,
    COUNT(DISTINCT pr.icd_code) AS num_imaging_studies  -- Distinct ICD codes as proxy for unique studies
  FROM 
    hf_admissions ha
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ha.hadm_id = pr.hadm_id
  WHERE 
    pr.icd_version = 10
    AND (
      -- Focus on imaging procedure codes (ICD-10-PCS)
      pr.icd_code LIKE 'BW%'  -- Broad imaging procedures (X-ray, CT, MRI, etc.)
      OR pr.icd_code IN (
        '4A023N7',  -- Echocardiography
        'BW3Z000',  -- Chest X-ray
        'BW25YZZ',  -- CT chest
        'B030YZZ'   -- MRI
      )
    )
  GROUP BY 
    ha.hadm_id, los_stratum, hf_type
),
aggregated_stats AS (
  SELECT 
    los_stratum,
    hf_type,
    -- Compute percentiles of imaging counts per admission
    PERCENTILE_CONT(0.25 RESPECT NULLS) OVER (PARTITION BY los_stratum, hf_type) AS p25,
    PERCENTILE_CONT(0.50 RESPECT NULLS) OVER (PARTITION BY los_stratum, hf_type) AS p50,
    PERCENTILE_CONT(0.75 RESPECT NULLS) OVER (PARTITION BY los_stratum, hf_type) AS p75,
    COUNT(*) AS num_admissions,
    AVG(num_imaging_studies) AS avg_imaging  -- Bonus: for reference
  FROM 
    imaging_counts
  GROUP BY 
    los_stratum, hf_type
)
SELECT 
  los_stratum,
  hf_type,
  ROUND(p25, 2) AS p25_imaging_per_admission,
  ROUND(p50, 2) AS p50_imaging_per_admission,
  ROUND(p75, 2) AS p75_imaging_per_admission,
  num_admissions
FROM 
  aggregated_stats
ORDER BY 
  los_stratum, hf_type;