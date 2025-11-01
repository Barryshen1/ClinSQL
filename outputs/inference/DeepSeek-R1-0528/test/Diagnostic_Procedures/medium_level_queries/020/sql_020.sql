WITH tia_admissions AS (
  SELECT 
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '435%') 
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 72 AND 82
    AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7
),
admissions_icu_flag AS (
  SELECT 
    ta.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE icu.hadm_id = ta.hadm_id
      ) 
      THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_use
  FROM tia_admissions ta
),
icd_imaging_codes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'(ct|mri|ultrasound|x-?ray|radiograph|scan|tomography|mammogram|angiogram)')
),
hcpcs_imaging_codes AS (
  SELECT 
    code AS hcpcs_cd
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE category IN (
    'Diagnostic Radiology', 'Diagnostic Ultrasound', 'Nuclear Medicine', 
    'Magnetic Resonance Imaging', 'Computed Tomography'
  )
),
imaging_events AS (
  -- Procedures_icd Events (ICD codes)
  SELECT 
    proc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN icd_imaging_codes img
    ON proc.icd_code = img.icd_code 
    AND proc.icd_version = img.icd_version
  UNION ALL
  -- HCPCSEvents
  SELECT 
    hcpc.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
  INNER JOIN hcpcs_imaging_codes img
    ON hcpc.hcpcs_cd = img.hcpcs_cd
),
imaging_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS imaging_count
  FROM imaging_events
  GROUP BY hadm_id
)
SELECT 
  a.los_group,
  a.icu_use,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(i.imaging_count, 0)) AS mean_imaging_procedures
FROM admissions_icu_flag a
LEFT JOIN imaging_counts i
  ON a.hadm_id = i.hadm_id
GROUP BY a.los_group, a.icu_use
ORDER BY a.los_group, a.icu_use;