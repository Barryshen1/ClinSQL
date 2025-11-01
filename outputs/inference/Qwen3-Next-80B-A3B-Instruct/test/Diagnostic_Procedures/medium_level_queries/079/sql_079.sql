WITH lgib_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days,
    di.seq_num,
    di.icd_code,
    di.icd_version,
    ddi.long_title
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi 
      ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(ddi.long_title) LIKE '%lower%gastrointestin%' 
    AND LOWER(ddi.long_title) LIKE '%bleed%'
    AND LOWER(ddi.long_title) NOT LIKE '%upper%'
),
ct_procedures AS (
  SELECT 
    i.hadm_id,
    COUNT(*) AS ct_count
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN 
    physionet-data.mimiciv_3_1_icu.procedureevents pe ON i.stay_id = pe.stay_id
  JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%ct%'
    OR LOWER(di.label) LIKE '%radiograph%'
    OR LOWER(di.label) LIKE '%x-ray%'
    OR LOWER(di.label) LIKE '%imaging%'
    OR LOWER(di.label) LIKE '%fluoroscopy%'
  GROUP BY 
    i.hadm_id
),
final_data AS (
  SELECT 
    la.hadm_id,
    la.los_days,
    la.seq_num,
    CASE 
      WHEN la.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN la.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'other'
    END AS los_group,
    CASE 
      WHEN la.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type,
    COALESCE(cp.ct_count, 0) AS ct_count
  FROM 
    lgib_admissions la
  LEFT JOIN 
    ct_procedures cp ON la.hadm_id = cp.hadm_id
  WHERE 
    la.los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  diagnosis_type,
  AVG(ct_count) AS mean_ct_count
FROM 
  final_data
GROUP BY 
  los_group, diagnosis_type
ORDER BY 
  los_group, diagnosis_type;