WITH aki_admissions AS (
  -- Identify AKI admissions, stratified by primary/secondary
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN d.seq_num = 1 THEN 'Primary AKI'
      ELSE 'Secondary AKI'
    END AS aki_type
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
    LOWER(icd.long_title) LIKE '%acute kidney%'  -- AKI diagnosis
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7  -- LOS 1-7 days
),

imaging_counts AS (
  -- Count MRI/CT events per admission
  SELECT 
    pe.hadm_id,
    COUNT(*) AS imaging_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE 
    (LOWER(di.label) LIKE '%mri%' OR LOWER(di.label) LIKE '%ct%' OR LOWER(di.label) LIKE '%cat%')
  GROUP BY pe.hadm_id
)

-- Final aggregation: patients and mean imaging, stratified
SELECT 
  aa.aki_type,
  CASE 
    WHEN aa.los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
    WHEN aa.los_days BETWEEN 5 AND 7 THEN 'LOS 5-7 days'
  END AS los_group,
  COUNT(DISTINCT aa.subject_id) AS patient_count,
  ROUND(AVG(COALESCE(ic.imaging_count, 0)), 2) AS mean_mri_ct_per_admission
FROM 
  aki_admissions aa
LEFT JOIN 
  imaging_counts ic
  ON aa.hadm_id = ic.hadm_id
GROUP BY 
  aa.aki_type, los_group
ORDER BY 
  aa.aki_type, 
  CASE los_group 
    WHEN 'LOS 1-4 days' THEN 1 
    ELSE 2 
  END;