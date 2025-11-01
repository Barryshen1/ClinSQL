WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    di.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON p.subject_id = di.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dic ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND LOWER(dic.long_title) LIKE '%lower gastrointestinal bleeding%'
       OR LOWER(dic.long_title) LIKE '%gastrointestinal hemorrhage%'
       OR LOWER(dic.long_title) LIKE '%colon hemorrhage%'
       OR LOWER(dic.long_title) LIKE '%rectal hemorrhage%'
       OR LOWER(dic.long_title) LIKE '%hematochezia%'
       OR LOWER(dic.long_title) LIKE '%lower gi bleed%'
       OR LOWER(dic.long_title) LIKE '%digestive tract hemorrhage%'
),

los_groups AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    EXTRACT(DAY FROM a.dischtime - a.admittime) AS los_days
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON c.hadm_id = a.hadm_id
  WHERE a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
),

icu_status AS (
  SELECT DISTINCT
    hadm_id,
    CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu_stay
  FROM physionet-data.mimiciv_3_1_icu.icustays
),

non_invasive_diagnostics AS (
  -- From ICU: procedureevents
  SELECT
    p.hadm_id
  FROM physionet-data.mimiciv_3_1_icu.procedureevents p
  JOIN physionet-data.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ct%'
     OR LOWER(d.label) LIKE '%mri%'
     OR LOWER(d.label) LIKE '%ultrasound%'
     OR LOWER(d.label) LIKE '%x-ray%'
     OR LOWER(d.label) LIKE '%radiograph%'
     OR LOWER(d.label) LIKE '%nuclear%'
     OR LOWER(d.label) LIKE '%mammogram%'
     OR LOWER(d.label) LIKE '%ecg%'
     OR LOWER(d.label) LIKE '%eeg%'
     OR LOWER(d.label) LIKE '%pft%'
     OR LOWER(d.label) LIKE '%pulmonary function%'
     OR LOWER(d.label) LIKE '%spirometry%'
     OR LOWER(d.label) LIKE '%lung function%'
     OR LOWER(d.label) LIKE '%ventilation%'
     OR LOWER(d.label) LIKE '%flow volume%'
     OR LOWER(d.label) LIKE '%peak flow%'
     OR LOWER(d.label) LIKE '%oximetry%'
     OR LOWER(d.label) LIKE '%abg%'
     OR LOWER(d.label) LIKE '%arterial blood gas%'
  
  UNION ALL
  
  -- From HOSP: hcpcsevents
  SELECT
    h.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs dh ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%ultrasound%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%radiograph%'
     OR LOWER(dh.short_description) LIKE '%nuclear%'
     OR LOWER(dh.short_description) LIKE '%mammogram%'
     OR LOWER(dh.short_description) LIKE '%ecg%'
     OR LOWER(dh.short_description) LIKE '%eeg%'
     OR LOWER(dh.short_description) LIKE '%pft%'
     OR LOWER(dh.short_description) LIKE '%pulmonary function%'
     OR LOWER(dh.short_description) LIKE '%spirometry%'
     OR LOWER(dh.short_description) LIKE '%lung function%'
     OR LOWER(dh.short_description) LIKE '%ventilation%'
     OR LOWER(dh.short_description) LIKE '%flow volume%'
     OR LOWER(dh.short_description) LIKE '%peak flow%'
     OR LOWER(dh.short_description) LIKE '%oximetry%'
     OR LOWER(dh.short_description) LIKE '%abg%'
     OR LOWER(dh.short_description) LIKE '%arterial blood gas%'
     OR LOWER(dh.long_description) LIKE '%ct%'
     OR LOWER(dh.long_description) LIKE '%mri%'
     OR LOWER(dh.long_description) LIKE '%ultrasound%'
     OR LOWER(dh.long_description) LIKE '%x-ray%'
     OR LOWER(dh.long_description) LIKE '%radiograph%'
     OR LOWER(dh.long_description) LIKE '%nuclear%'
     OR LOWER(dh.long_description) LIKE '%mammogram%'
     OR LOWER(dh.long_description) LIKE '%ecg%'
     OR LOWER(dh.long_description) LIKE '%eeg%'
     OR LOWER(dh.long_description) LIKE '%pft%'
     OR LOWER(dh.long_description) LIKE '%pulmonary function%'
     OR LOWER(dh.long_description) LIKE '%spirometry%'
     OR LOWER(dh.long_description) LIKE '%lung function%'
     OR LOWER(dh.long_description) LIKE '%ventilation%'
     OR LOWER(dh.long_description) LIKE '%flow volume%'
     OR LOWER(dh.long_description) LIKE '%peak flow%'
     OR LOWER(dh.long_description) LIKE '%oximetry%'
     OR LOWER(dh.long_description) LIKE '%abg%'
     OR LOWER(dh.long_description) LIKE '%arterial blood gas%'
),

diag_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_diagnostics
  FROM non_invasive_diagnostics
  GROUP BY hadm_id
)

SELECT
  CASE
    WHEN l.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN l.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'other'
  END AS los_group,
  COALESCE(i.has_icu_stay, 0) AS has_icu_stay,
  AVG(COALESCE(d.num_diagnostics, 0)) AS mean_non_invasive_diagnostics_per_admission
FROM los_groups l
LEFT JOIN icu_status i ON l.hadm_id = i.hadm_id
LEFT JOIN diag_counts d ON l.hadm_id = d.hadm_id
GROUP BY los_group, has_icu_stay
ORDER BY los_group, has_icu_stay;