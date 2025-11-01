WITH cohort AS (
  -- Base cohort: admissions for 64yo male with HF
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    p.gender,
    p.anchor_age,
    -- ICU flag: any ICU stay in admission
    CASE WHEN COUNT(DISTINCT i.stay_id) > 0 THEN 1 ELSE 0 END AS icu_flag
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
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age = 64
    AND icd.icd_code LIKE 'I50%'  -- Heart failure (ICD-10)
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8
  GROUP BY 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.gender, p.anchor_age
),

imaging_counts AS (
  -- Count distinct imaging events per admission
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT ce.charttime) AS imaging_count,
    CASE 
      WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
      ELSE '5-8'
    END AS los_group,
    CASE WHEN c.icu_flag = 1 THEN 'Yes' ELSE 'No' END AS icu_use
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.hadm_id = ce.hadm_id
    AND ce.itemid IN (220045, 220046, 220224, 220225, 220254)  -- Radiography/CT itemids
    AND ce.valuenum IS NOT NULL  -- Valid numeric values
  GROUP BY 
    c.hadm_id, los_group, icu_use
)

-- Compute percentiles by group
SELECT 
  los_group,
  icu_use,
  PERCENTILE_CONT(imaging_count, 0.25) OVER (PARTITION BY los_group, icu_use) AS p25,
  PERCENTILE_CONT(imaging_count, 0.50) OVER (PARTITION BY los_group, icu_use) AS p50,
  PERCENTILE_CONT(imaging_count, 0.75) OVER (PARTITION BY los_group, icu_use) AS p75
FROM 
  imaging_counts
GROUP BY 
  los_group, icu_use, imaging_count
ORDER BY 
  los_group, icu_use;