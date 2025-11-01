WITH target_patients AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 44 AND 54
),
tia_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi 
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE ddi.long_title LIKE '%transient ischemic attack%' 
    OR ddi.long_title LIKE '%TIA%'
),
los_data AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM tia_admissions
),
icu_use AS (
  SELECT 
    hadm_id,
    CASE WHEN COUNT(stay_id) > 0 THEN 1 ELSE 0 END AS has_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
icu_imaging AS (
  SELECT 
    pe.hadm_id,
    COUNT(*) AS icu_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%CT%' 
    OR di.label LIKE '%MRI%' 
    OR di.label LIKE '%X-RAY%' 
    OR di.label LIKE '%ULTRASOUND%' 
    OR di.label LIKE '%FLUOROSCOPY%' 
    OR di.label LIKE '%ANGIOGRAPHY%' 
    OR di.label LIKE '%RAD%' 
    OR di.label LIKE '%IMAGING%'
  GROUP BY pe.hadm_id
),
hosp_imaging AS (
  SELECT 
    hc.hadm_id,
    COUNT(*) AS hosp_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  WHERE hc.short_description LIKE '%CT%' 
    OR hc.short_description LIKE '%MRI%' 
    OR hc.short_description LIKE '%X-RAY%' 
    OR hc.short_description LIKE '%ULTRASOUND%' 
    OR hc.short_description LIKE '%FLUOROSCOPY%' 
    OR hc.short_description LIKE '%ANGIOGRAPHY%' 
    OR hc.short_description LIKE '%RAD%' 
    OR hc.short_description LIKE '%IMAGING%'
  GROUP BY hc.hadm_id
),
imaging_counts AS (
  SELECT 
    COALESCE(icu.hadm_id, hosp.hadm_id) AS hadm_id,
    COALESCE(icu.icu_count, 0) + COALESCE(hosp.hosp_count, 0) AS total_imaging
  FROM icu_imaging icu
  FULL OUTER JOIN hosp_imaging hosp ON icu.hadm_id = hosp.hadm_id
),
final_data AS (
  SELECT 
    los.los_days,
    COALESCE(icu.has_icu, 0) AS has_icu,
    ic.total_imaging,
    CASE 
      WHEN los.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los.los_days BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_category
  FROM los_data los
  LEFT JOIN icu_use icu ON los.hadm_id = icu.hadm_id
  LEFT JOIN imaging_counts ic ON los.hadm_id = ic.hadm_id
  WHERE los.los_days BETWEEN 1 AND 7
)
SELECT 
  los_category,
  has_icu,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_imaging) AS p25,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_imaging) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_imaging) AS p75
FROM final_data
WHERE los_category IS NOT NULL
GROUP BY los_category, has_icu
ORDER BY los_category, has_icu;