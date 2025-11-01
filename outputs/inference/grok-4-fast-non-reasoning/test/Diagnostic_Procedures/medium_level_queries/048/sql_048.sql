WITH cohort AS (
  -- Base admissions with patient demographics and LOS
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 7
),

hf_diagnoses AS (
  -- Heart failure diagnoses (ICD-10 I50*)
  SELECT 
    di.subject_id,
    di.hadm_id,
    di.seq_num,
    di.icd_code,
    dd.long_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON di.icd_code = dd.icd_code 
    AND di.icd_version = dd.icd_version
  WHERE 
    di.icd_version = '10'
    AND di.icd_code LIKE 'I50%'
    -- Optional: AND dd.long_title LIKE '%heart failure%' for stricter match
),

hf_cohort AS (
  -- Apply HF filter to cohort
  SELECT 
    c.*,
    hd.seq_num,
    CASE 
      WHEN CAST(hd.seq_num AS INT64) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type,
    CASE 
      WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days'
    END AS los_group
  FROM 
    cohort c
  INNER JOIN 
    hf_diagnoses hd
  ON c.hadm_id = hd.hadm_id
),

imaging AS (
  -- MRI/CT counts per admission using HCPCS (simplified prefixes; expand as needed)
  SELECT 
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON h.hcpcs_cd = d.code
  WHERE 
    (h.hcpcs_cd LIKE '7%'  -- Broad CT/MRI (e.g., 70XXX-71XXX for CT, 70XXX for MRI)
     AND (d.short_description LIKE '%CT%' 
     OR d.short_description LIKE '%MRI%' 
     OR d.short_description LIKE '%computed tomography%' 
     OR d.short_description LIKE '%magnetic resonance%'))
  GROUP BY 
    h.subject_id, h.hadm_id
),

imaging_per_adm AS (
  -- Add imaging to cohort (0 if no imaging)
  SELECT 
    hc.*,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM 
    hf_cohort hc
  LEFT JOIN 
    imaging i
  ON hc.hadm_id = i.hadm_id
)

-- Final aggregation
SELECT 
  hf_type,
  los_group,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(imaging_count), 2) AS mean_mri_ct_per_admission
FROM 
  imaging_per_adm
GROUP BY 
  hf_type, 
  los_group
ORDER BY 
  hf_type, 
  los_group;