WITH eligible_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 67 AND 77
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
hf_admissions AS (
  SELECT 
    diag.hadm_id,
    CASE 
      WHEN MAX(CASE WHEN diag.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
    (d.icd_version = 9 AND d.icd_code LIKE '428%') 
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
  GROUP BY diag.hadm_id
),
imaging_events AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%x-ray%'
    OR LOWER(dicd.long_title) LIKE '%ct%'
    OR LOWER(dicd.long_title) LIKE '%mri%'
    OR LOWER(dicd.long_title) LIKE '%ultrasound%'
    OR LOWER(dicd.long_title) LIKE '%echocardiogram%'
    OR LOWER(dicd.long_title) LIKE '%angiography%'
    OR LOWER(dicd.long_title) LIKE '%scan%'
  UNION ALL
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON hcpc.hcpcs_cd = dh.code
  WHERE 
    LOWER(dh.long_description) LIKE '%x-ray%'
    OR LOWER(dh.long_description) LIKE '%ct%'
    OR LOWER(dh.long_description) LIKE '%mri%'
    OR LOWER(dh.long_description) LIKE '%ultrasound%'
    OR LOWER(dh.long_description) LIKE '%echocardiogram%'
    OR LOWER(dh.long_description) LIKE '%angiography%'
    OR LOWER(dh.long_description) LIKE '%scan%'
),
imaging_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS imaging_count
  FROM imaging_events
  GROUP BY hadm_id
),
combined_data AS (
  SELECT 
    ea.hadm_id,
    ea.los_days,
    hf.hf_type,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM eligible_admissions ea
  INNER JOIN hf_admissions hf
    ON ea.hadm_id = hf.hadm_id
  LEFT JOIN imaging_counts ic
    ON ea.hadm_id = ic.hadm_id
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  hf_type,
  APPROX_QUANTILES(imaging_count, 4)[SAFE_OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[SAFE_OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[SAFE_OFFSET(3)] AS p75
FROM combined_data
WHERE los_days BETWEEN 1 AND 7
GROUP BY los_group, hf_type
ORDER BY los_group, hf_type;