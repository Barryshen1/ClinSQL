WITH lower_gi_bleed_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'lower\s*gi\s*(bleed|hemorrhage)|gastrointestinal\s*hemorrhage')
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN lower_gi_bleed_codes lgb
    ON diag.icd_code = lgb.icd_code 
    AND diag.icd_version = lgb.icd_version
  WHERE 
    pt.gender = 'F'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 62 AND 72
),
icu_status AS (
  SELECT 
    hadm_id, 
    MAX(CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END) AS had_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
non_invasive_procedures AS (
  -- ICD Procedures
  SELECT 
    proc.hadm_id,
    d.long_title AS description
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code 
    AND proc.icd_version = d.icd_version
  WHERE 
    REGEXP_CONTAINS(LOWER(d.long_title), r'(x-ray|xray|radiograph|ct scan|computed tomography|mri|magnetic resonance imaging|ultrasound|sonogram|echocardiogram|ecg|ekg|electrocardiogram|eeg|electroencephalogram|pulmonary function test|pft|spirometry)')
    AND NOT REGEXP_CONTAINS(LOWER(d.long_title), r'catheter|biopsy|invasive|surgery')

  UNION ALL

  -- HCPCS Procedures
  SELECT 
    hcpcs.hadm_id,
    COALESCE(d.short_description, d.long_description) AS description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpcs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON hcpcs.hcpcs_cd = d.code
  WHERE 
    REGEXP_CONTAINS(LOWER(COALESCE(d.short_description, d.long_description)), r'(x-ray|xray|radiograph|ct scan|computed tomography|mri|magnetic resonance imaging|ultrasound|sonogram|echocardiogram|ecg|ekg|electrocardiogram|eeg|electroencephalogram|pulmonary function test|pft|spirometry)')
    AND NOT REGEXP_CONTAINS(LOWER(COALESCE(d.short_description, d.long_description)), r'catheter|biopsy|invasive|surgery')
),
procedure_counts AS (
  SELECT 
    hadm_id, 
    COUNT(*) AS num_procedures
  FROM non_invasive_procedures
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN c.los_days BETWEEN 1 AND 3 THEN '1-3 days' 
    WHEN c.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  CASE 
    WHEN icu.had_icu = 1 THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  AVG(COALESCE(pc.num_procedures, 0)) AS mean_procedures_per_admission
FROM cohort c
LEFT JOIN icu_status icu
  ON c.hadm_id = icu.hadm_id
LEFT JOIN procedure_counts pc
  ON c.hadm_id = pc.hadm_id
WHERE c.los_days BETWEEN 1 AND 7
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;