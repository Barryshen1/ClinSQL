WITH stroke_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(d_icd.long_title) LIKE '%ischemic stroke%'
    AND LOWER(d_icd.long_title) LIKE '%cerebral infarction%'
),

icu_stays_with_los AS (
  SELECT i.stay_id, i.hadm_id, i.los
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN stroke_patients sp ON i.hadm_id = sp.hadm_id
  WHERE i.los BETWEEN 1 AND 7
),

imaging_procedures AS (
  SELECT pe.hadm_id, pe.stay_id
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  JOIN icu_stays_with_los is_los ON pe.stay_id = is_los.stay_id
  WHERE LOWER(di.label) LIKE '%ct%'
     OR LOWER(di.label) LIKE '%mri%'
     OR LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%angiography%'
     OR LOWER(di.label) LIKE '%x-ray%'
     OR LOWER(di.label) LIKE '%pet%'
     OR LOWER(di.label) LIKE '%nuclear%'
     OR LOWER(di.label) LIKE '%fluoroscopy%'
     OR LOWER(di.label) LIKE '%imaging%'
     OR LOWER(di.label) LIKE '%scan%'
     OR LOWER(di.label) LIKE '%radiograph%'
),

imaging_counts_per_admission AS (
  SELECT hadm_id, COUNT(*) AS num_imaging_procedures
  FROM imaging_procedures
  GROUP BY hadm_id
),

stratified_counts AS (
  SELECT 
    CASE 
      WHEN is_los.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN is_los.los BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    ic.num_imaging_procedures
  FROM icu_stays_with_los is_los
  JOIN imaging_counts_per_admission ic ON is_los.hadm_id = ic.hadm_id
)

SELECT 
  los_group,
  AVG(num_imaging_procedures) AS mean_procedures,
  MIN(num_imaging_procedures) AS min_procedures,
  MAX(num_imaging_procedures) AS max_procedures
FROM stratified_counts
WHERE los_group IS NOT NULL
GROUP BY los_group
ORDER BY los_group;