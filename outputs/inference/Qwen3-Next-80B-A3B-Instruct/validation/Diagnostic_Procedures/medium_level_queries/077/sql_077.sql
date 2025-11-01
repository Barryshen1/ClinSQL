WITH filtered_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 57 AND 67
),
admissions_with_los AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  WHERE a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
icu_flag AS (
  SELECT DISTINCT hadm_id, TRUE AS has_icu
  FROM physionet-data.mimiciv_3_1_icu.icustays
),
ultrasound_procedures AS (
  -- ICU procedureevents: join with d_items and icustays to get hadm_id
  SELECT pe.hadm_id
  FROM physionet-data.mimiciv_3_1_icu.procedureevents pe
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays icu ON pe.stay_id = icu.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%echo%' 
     OR LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%cardiac ultrasound%'
     OR LOWER(di.label) LIKE '%echocardiogram%'
     OR LOWER(di.label) LIKE '%echo study%'
     OR LOWER(di.label) LIKE '%ultrasound study%'
  
  UNION ALL
  
  -- HOSP hcpcsevents: use HCPCS codes for non-ICU procedures
  SELECT h.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_hcpcs dh ON h.hcpcs_cd = dh.code
  WHERE LOWER(dh.short_description) LIKE '%echo%' 
     OR LOWER(dh.short_description) LIKE '%ultrasound%'
     OR LOWER(dh.short_description) LIKE '%echocardiogram%'
     OR LOWER(dh.short_description) LIKE '%cardiac ultrasound%'
     OR LOWER(dh.short_description) LIKE '%echo study%'
     OR LOWER(dh.short_description) LIKE '%ultrasound study%'
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM ultrasound_procedures
  GROUP BY hadm_id
),
admission_ultrasound_counts AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    COALESCE(i.has_icu, FALSE) AS has_icu,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM admissions_with_los a
  LEFT JOIN icu_flag i ON a.hadm_id = i.hadm_id
  LEFT JOIN ultrasound_counts u ON a.hadm_id = u.hadm_id
),
stratified_groups AS (
  SELECT 
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    has_icu,
    ultrasound_count
  FROM admission_ultrasound_counts
  WHERE los_days BETWEEN 1 AND 7
)
SELECT 
  los_group,
  has_icu,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75
FROM stratified_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, has_icu
ORDER BY los_group, has_icu;