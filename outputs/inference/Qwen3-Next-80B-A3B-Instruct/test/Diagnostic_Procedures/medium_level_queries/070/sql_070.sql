WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND did.icd_code LIKE 'I50%'
    AND did.icd_version = 10
),
los_categories AS (
  SELECT 
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM heart_failure_patients
  WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 8
),
icu_flag AS (
  SELECT DISTINCT hadm_id, 1 AS has_icu
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
imaging_procedures AS (
  -- HOSP module: HCPCS events
  SELECT hadm_id, COUNT(*) AS proc_count
  FROM physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%ct%'
     OR LOWER(d.short_description) LIKE '%x-ray%'
     OR LOWER(d.short_description) LIKE '%radiograph%'
     OR LOWER(d.short_description) LIKE '%radiology%'
  GROUP BY hadm_id

  UNION ALL

  -- ICU module: procedureevents
  SELECT hadm_id, COUNT(*) AS proc_count
  FROM physionet-data.mimiciv_3_1_icu.procedureevents p
  JOIN physionet-data.mimiciv_3_1_icu.d_items d ON p.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ct%'
     OR LOWER(d.label) LIKE '%x-ray%'
     OR LOWER(d.label) LIKE '%radiograph%'
     OR LOWER(d.label) LIKE '%radiology%'
  GROUP BY hadm_id
),
total_imaging_per_admission AS (
  SELECT hadm_id, SUM(proc_count) AS total_imaging_procs
  FROM imaging_procedures
  GROUP BY hadm_id
),
final_data AS (
  SELECT 
    l.los_group,
    COALESCE(i.has_icu, 0) AS has_icu,
    COALESCE(t.total_imaging_procs, 0) AS imaging_count
  FROM los_categories l
  LEFT JOIN icu_flag i ON l.hadm_id = i.hadm_id
  LEFT JOIN total_imaging_per_admission t ON l.hadm_id = t.hadm_id
)
SELECT 
  los_group,
  has_icu,
  PERCENTILE_CONT(imaging_count, 0.25) AS p25,
  PERCENTILE_CONT(imaging_count, 0.50) AS p50,
  PERCENTILE_CONT(imaging_count, 0.75) AS p75
FROM final_data
GROUP BY los_group, has_icu
ORDER BY los_group, has_icu;