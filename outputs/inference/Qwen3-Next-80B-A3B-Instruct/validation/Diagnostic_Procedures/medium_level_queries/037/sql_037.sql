WITH amipatients AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

imaging_procedures AS (
  -- ICU procedureevents: CT, X-ray, Radiography
  SELECT 
    pe.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ct%'
     OR LOWER(di.label) LIKE '%x-ray%'
     OR LOWER(di.label) LIKE '%radiography%'
     OR LOWER(di.label) LIKE '%radiologic%'
  GROUP BY pe.hadm_id

  UNION ALL

  -- HOSP hcpcsevents: imaging procedures
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%radiography%'
     OR LOWER(dh.short_description) LIKE '%radiologic%'
  GROUP BY h.hadm_id
),

imaging_counts AS (
  SELECT 
    hadm_id,
    SUM(imaging_count) AS total_imaging_procedures
  FROM imaging_procedures
  GROUP BY hadm_id
),

final_data AS (
  SELECT 
    ap.los_days,
    ap.ami_type,
    COALESCE(ic.total_imaging_procedures, 0) AS imaging_count
  FROM amipatients ap
  LEFT JOIN imaging_counts ic 
    ON ap.hadm_id = ic.hadm_id
)

SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  ami_type,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median_imaging,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS q1_imaging,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS q3_imaging
FROM final_data
GROUP BY los_group, ami_type
ORDER BY los_group, ami_type;