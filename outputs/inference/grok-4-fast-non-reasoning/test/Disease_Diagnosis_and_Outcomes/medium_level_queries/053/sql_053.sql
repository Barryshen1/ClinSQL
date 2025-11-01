WITH cohort AS (
  -- Base cohort: male, 39-49, pneumonia admissions
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Pneumonia type (primary diagnosis only)
    CASE 
      WHEN d.icd_code LIKE 'J15%' THEN 'Community-acquired'
      WHEN d.icd_code LIKE 'J69%' THEN 'Aspiration'
      ELSE NULL 
    END AS pneumonia_type,
    -- Day-1 ICU status (1 if any ICU admit within 1 day of hospital admit)
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.subject_id = a.subject_id
          AND t.hadm_id = a.hadm_id
          AND t.eventtype = 'admit'
          AND t.careunit LIKE '%ICU%'
          AND t.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 1 ELSE 0 
    END AS icu_day1
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id 
    AND d.seq_num = CAST(1 AS INT64)  -- Primary diagnosis, type fix
    AND d.icd_version = 'ICD-10-CM'
    AND (d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J69%')  -- Pneumonia filter
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.dischtime IS NOT NULL  -- Valid discharge
),

comorbidities AS (
  -- Count secondary ICD codes per admission (comorbidity proxy)
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_version = 'ICD-10-CM'
    AND seq_num > 1  -- Exclude primary diagnosis
  GROUP BY 
    subject_id, hadm_id
)

-- Main aggregation
SELECT 
  pneumonia_type,
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN los_days >= 8 THEN '>=8 days'
    ELSE 'Other'
  END AS los_bin,
  icu_day1,
  -- Mortality %
  ROUND((SUM(hospital_expire_flag) * 100.0 / COUNT(*)), 2) AS mortality_pct,
  -- Average comorbidity count
  ROUND(AVG(COALESCE(com.comorbidity_count, 0)), 2) AS avg_comorbidity_count,
  -- Community-acquired baseline for this bin (for diffs)
  ROUND((SUM(CASE WHEN pneumonia_type = 'Community-acquired' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
         NULLIF(SUM(CASE WHEN pneumonia_type = 'Community-acquired' THEN 1 ELSE 0 END), 0)), 2) AS mort_pct_community,
  -- Absolute difference (only for Aspiration vs Community)
  CASE WHEN pneumonia_type = 'Aspiration' THEN 
    ROUND(mortality_pct - 
          (SUM(CASE WHEN pneumonia_type = 'Community-acquired' THEN hospital_expire_flag ELSE 0 END) * 100.0 / 
           NULLIF(SUM(CASE WHEN pneumonia_type = 'Community-acquired' THEN 1 ELSE 0 END), 0)), 2)
  ELSE NULL END AS absolute_diff,
  -- Relative difference % (only for Aspiration vs Community)
  CASE WHEN pneumonia_type = 'Aspiration' AND mort_pct_community > 0 THEN 
    ROUND(((mortality_pct / mort_pct_community) - 1) * 100, 2)
  ELSE NULL END AS relative_diff_pct,
  COUNT(*) AS n_patients
FROM 
  cohort c
LEFT JOIN 
  comorbidities com ON c.subject_id = com.subject_id AND c.hadm_id = com.hadm_id
WHERE 
  pneumonia_type IS NOT NULL
  AND los_days > 0  -- Exclude same-day discharges
GROUP BY 
  pneumonia_type, los_bin, icu_day1
ORDER BY 
  los_bin, icu_day1, pneumonia_type;