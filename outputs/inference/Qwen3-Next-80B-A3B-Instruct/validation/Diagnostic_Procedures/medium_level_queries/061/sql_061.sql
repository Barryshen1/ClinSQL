WITH akipatients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    p.gender,
    d.hadm_id,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data`.mimiciv_3_1_hosp.patients p
  JOIN `physionet-data`.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND LOWER(dicd.long_title) LIKE '%acute kidney injury%'
),

icu_los AS (
  SELECT
    hadm_id,
    SUM(TIMESTAMP_DIFF(outtime, intime, DAY)) AS total_los_days
  FROM `physionet-data`.mimiciv_3_1_icu.icustays
  GROUP BY hadm_id
),

imaging_procedures AS (
  -- ICU procedureevents with imaging
  SELECT
    pe.hadm_id,
    pe.starttime,
    di.label AS procedure_label
  FROM `physionet-data`.mimiciv_3_1_icu.procedureevents pe
  JOIN `physionet-data`.mimiciv_3_1_icu.d_items di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ct%'
     OR LOWER(di.label) LIKE '%mri%'
     OR LOWER(di.label) LIKE '%x-ray%'
     OR LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%radiology%'
     OR LOWER(di.label) LIKE '%imaging%'
     OR LOWER(di.label) LIKE '%scan%'
     OR LOWER(di.label) LIKE '%fluoroscopy%'
     OR LOWER(di.label) LIKE '%nuclear medicine%'
     OR LOWER(di.label) LIKE '%dxa%'
     OR LOWER(di.label) LIKE '%mammography%'
     OR LOWER(di.label) LIKE '%angiography%'
     OR LOWER(di.label) LIKE '%sonography%'
     OR LOWER(di.label) LIKE '%doppler%'
     OR LOWER(di.label) LIKE '%pet%'
     OR LOWER(di.label) LIKE '%spect%'

  UNION ALL

  -- HOSP hcpcsevents with imaging
  SELECT
    h.hadm_id,
    h.chartdate AS starttime,
    dh.short_description AS procedure_label
  FROM `physionet-data`.mimiciv_3_1_hosp.hcpcsevents h
  JOIN `physionet-data`.mimiciv_3_1_hosp.d_hcpcs dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%ct%'
     OR LOWER(dh.short_description) LIKE '%mri%'
     OR LOWER(dh.short_description) LIKE '%x-ray%'
     OR LOWER(dh.short_description) LIKE '%ultrasound%'
     OR LOWER(dh.short_description) LIKE '%radiology%'
     OR LOWER(dh.short_description) LIKE '%imaging%'
     OR LOWER(dh.short_description) LIKE '%scan%'
     OR LOWER(dh.short_description) LIKE '%fluoroscopy%'
     OR LOWER(dh.short_description) LIKE '%nuclear medicine%'
     OR LOWER(dh.short_description) LIKE '%dxa%'
     OR LOWER(dh.short_description) LIKE '%mammography%'
     OR LOWER(dh.short_description) LIKE '%angiography%'
     OR LOWER(dh.short_description) LIKE '%sonography%'
     OR LOWER(dh.short_description) LIKE '%doppler%'
     OR LOWER(dh.short_description) LIKE '%pet%'
     OR LOWER(dh.short_description) LIKE '%spect%'
),

imaging_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_imaging_studies
  FROM imaging_procedures
  GROUP BY hadm_id
),

final_data AS (
  SELECT
    ap.hadm_id,
    ap.diagnosis_type,
    COALESCE(il.total_los_days, 0) AS total_los_days,
    COALESCE(ic.num_imaging_studies, 0) AS num_imaging_studies
  FROM akipatients ap
  LEFT JOIN icu_los il ON ap.hadm_id = il.hadm_id
  LEFT JOIN imaging_counts ic ON ap.hadm_id = ic.hadm_id
  WHERE COALESCE(il.total_los_days, 0) BETWEEN 1 AND 7
)

SELECT
  CASE 
    WHEN total_los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN total_los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  diagnosis_type,
  PERCENTILE_CONT(num_imaging_studies, 0.5) OVER () AS median_imaging,
  PERCENTILE_CONT(num_imaging_studies, 0.25) OVER () AS q1_imaging,
  PERCENTILE_CONT(num_imaging_studies, 0.75) OVER () AS q3_imaging
FROM final_data
ORDER BY los_group, diagnosis_type;