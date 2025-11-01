WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM `physionet-data`.mimiciv_3_1_hosp.patients p
  JOIN `physionet-data`.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.anchor_age = 74
    AND p.gender = 'F'
    AND LOWER(did.long_title) LIKE '%heart failure%'
),

icu_stays_filtered AS (
  SELECT i.stay_id, i.hadm_id, i.los,
    CASE 
      WHEN i.los >= 1 AND i.los <= 4 THEN '1-4 days'
      WHEN i.los >= 5 AND i.los <= 7 THEN '5-7 days'
    END AS stay_duration_group
  FROM `physionet-data`.mimiciv_3_1_icu.icustays i
  JOIN heart_failure_patients hfp ON i.hadm_id = hfp.hadm_id
  WHERE i.los >= 1 AND i.los <= 7
),

admission_types AS (
  SELECT a.hadm_id,
    CASE 
      WHEN a.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
      WHEN a.admission_type = 'ELECTIVE' THEN 'Elective'
    END AS admission_type_group
  FROM `physionet-data`.mimiciv_3_1_hosp.admissions a
  JOIN icu_stays_filtered isf ON a.hadm_id = isf.hadm_id
  WHERE a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

non_invasive_diagnostics AS (
  -- ICU procedureevents: non-invasive diagnostics
  SELECT DISTINCT pe.hadm_id, pe.itemid
  FROM `physionet-data`.mimiciv_3_1_icu.procedureevents pe
  JOIN `physionet-data`.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) IN (
    'ecg', 'ekg', 'electrocardiogram',
    'chest x-ray', 'cxr',
    'ct head', 'ct brain', 'ct chest', 'ct abdomen', 'ct pelvis',
    'mri brain', 'mri spine', 'mri chest',
    'ultrasound abdomen', 'ultrasound cardiac', 'echocardiogram',
    'pft', 'pulmonary function test',
    'eeg', 'electroencephalogram',
    'x-ray chest', 'x-ray head', 'x-ray abdomen'
  )
  
  UNION ALL
  
  -- HCPCSEvents: non-invasive diagnostics
  SELECT DISTINCT h.hadm_id, h.hcpcs_cd AS itemid
  FROM `physionet-data`.mimiciv_3_1_hosp.hcpcsevents h
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_hcpcs dh ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ecg%' 
     OR LOWER(dh.short_description) LIKE '%ekg%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%ultrasound%'
     OR LOWER(dh.short_description) LIKE '%pft%'
     OR LOWER(dh.short_description) LIKE '%eeg%'
     OR LOWER(dh.short_description) LIKE '%echocardiogram%'
     OR LOWER(dh.long_description) LIKE '%electrocardiogram%'
     OR LOWER(dh.long_description) LIKE '%pulmonary function test%'
     OR LOWER(dh.long_description) LIKE '%electroencephalogram%'
),

diagnostics_per_admission AS (
  SELECT 
    af.hadm_id,
    af.stay_duration_group,
    at.admission_type_group,
    COUNT(nid.itemid) AS diagnostic_count
  FROM icu_stays_filtered af
  JOIN admission_types at ON af.hadm_id = at.hadm_id
  LEFT JOIN non_invasive_diagnostics nid ON af.hadm_id = nid.hadm_id
  GROUP BY af.hadm_id, af.stay_duration_group, at.admission_type_group
)

SELECT 
  stay_duration_group,
  admission_type_group,
  AVG(diagnostic_count) AS mean_diagnostics_per_admission
FROM diagnostics_per_admission
WHERE stay_duration_group IS NOT NULL
  AND admission_type_group IS NOT NULL
GROUP BY stay_duration_group, admission_type_group
ORDER BY stay_duration_group, admission_type_group;