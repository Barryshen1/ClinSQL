WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 52 AND 62
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
anticoagulant_prescriptions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%warfarin%' OR
    LOWER(drug) LIKE '%heparin%' OR
    LOWER(drug) LIKE '%enoxaparin%' OR
    LOWER(drug) LIKE '%apixaban%' OR
    LOWER(drug) LIKE '%rivaroxaban%' OR
    LOWER(drug) LIKE '%dabigatran%' OR
    LOWER(drug) LIKE '%edoxaban%' OR
    LOWER(drug) LIKE '%fondaparinux%' OR
    LOWER(drug) LIKE '%coumadin%' OR
    LOWER(drug) LIKE '%lovenox%' OR
    LOWER(drug) LIKE '%eliquis%' OR
    LOWER(drug) LIKE '%xarelto%' OR
    LOWER(drug) LIKE '%pradaxa%' OR
    LOWER(drug) LIKE '%savaysa%' OR
    LOWER(drug) LIKE '%arixtra%'
)
SELECT 
  STDDEV(TIMESTAMP_DIFF(fa.dischtime, fa.admittime, DAY)) AS los_stddev
FROM first_admissions fa
JOIN anticoagulant_prescriptions ap 
  ON fa.hadm_id = ap.hadm_id;