WITH patients_filtered AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

ischemic_stroke_admissions AS (
  SELECT 
    pf.subject_id, 
    pf.hadm_id, 
    pf.admittime, 
    pf.dischtime
  FROM patients_filtered pf
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON pf.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON di.icd_code = dicd.icd_code 
    AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%ischemic stroke%' 
    OR dicd.long_title LIKE '%cerebral infarction%'
),

hospital_los AS (
  SELECT 
    isa.hadm_id,
    TIMESTAMP_DIFF(isa.dischtime, isa.admittime, DAY) AS los_days
  FROM ischemic_stroke_admissions isa
  WHERE TIMESTAMP_DIFF(isa.dischtime, isa.admittime, DAY) BETWEEN 1 AND 7
),

icu_presence AS (
  SELECT 
    h.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS in_icu
  FROM hospital_los h
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON h.hadm_id = i.hadm_id
),

imaging_counts AS (
  SELECT 
    ce.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE di.label LIKE '%CT%' 
    OR di.label LIKE '%MRI%' 
    OR di.label LIKE '%X-ray%' 
    OR di.label LIKE '%ultrasound%' 
    OR di.label LIKE '%fluoroscopy%'
  GROUP BY ce.hadm_id
),

final_data AS (
  SELECT 
    ip.hadm_id,
    ip.in_icu,
    CASE 
      WHEN h.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN h.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM icu_presence ip
  JOIN hospital_los h ON ip.hadm_id = h.hadm_id
  LEFT JOIN imaging_counts ic ON ip.hadm_id = ic.hadm_id
)

SELECT 
  los_group,
  in_icu,
  AVG(imaging_count) AS mean_imaging,
  MIN(imaging_count) AS min_imaging,
  MAX(imaging_count) AS max_imaging
FROM final_data
GROUP BY los_group, in_icu
ORDER BY los_group, in_icu;