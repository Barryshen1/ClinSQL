WITH patients_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS died,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) >= 1
),
upper_gi AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (LOWER(dd.long_title) LIKE '%hemorrhage%' OR LOWER(dd.long_title) LIKE '%bleed%')
    AND (LOWER(dd.long_title) LIKE '%upper%' OR LOWER(dd.long_title) LIKE '%gastric%' 
         OR LOWER(dd.long_title) LIKE '%duoden%' OR LOWER(dd.long_title) LIKE '%peptic%' 
         OR LOWER(dd.long_title) LIKE '%esophag%' OR LOWER(dd.long_title) LIKE '%stomach%' 
         OR LOWER(dd.long_title) LIKE '%varices%')
),
lower_gi AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (LOWER(dd.long_title) LIKE '%hemorrhage%' OR LOWER(dd.long_title) LIKE '%bleed%')
    AND (LOWER(dd.long_title) LIKE '%lower%' OR LOWER(dd.long_title) LIKE '%colon%' 
         OR LOWER(dd.long_title) LIKE '%diverticul%' OR LOWER(dd.long_title) LIKE '%rectal%' 
         OR LOWER(dd.long_title) LIKE '%anal%' OR LOWER(dd.long_title) LIKE '%small intestine%' 
         OR LOWER(dd.long_title) LIKE '%ileal%')
),
bleed_adm AS (
  SELECT 
    pa.*,
    CASE 
      WHEN ug.hadm_id IS NOT NULL THEN 'Upper'
      WHEN lg.hadm_id IS NOT NULL THEN 'Lower'
      ELSE NULL 
    END AS bleed_type
  FROM patients_admissions pa
  LEFT JOIN upper_gi ug ON pa.hadm_id = ug.hadm_id
  LEFT JOIN lower_gi lg ON pa.hadm_id = lg.hadm_id
  WHERE ug.hadm_id IS NOT NULL OR lg.hadm_id IS NOT NULL
),
icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime,
    TIMESTAMP_DIFF(i.intime, ba.admittime, HOUR) AS hours_from_admit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN bleed_adm ba ON i.subject_id = ba.subject_id AND i.hadm_id = ba.hadm_id
  WHERE i.intime >= ba.admittime
),
has_icu AS (
  SELECT 
    ba.subject_id,
    ba.hadm_id,
    ba.gender,
    ba.anchor_age,
    ba.admittime,
    ba.dischtime,
    ba.died,
    ba.los_days,
    ba.bleed_type,
    COALESCE(MAX(CASE WHEN is.hadm_id IS NOT NULL AND is.hours_from_admit <= 24 THEN 1 ELSE 0 END), 0) AS day1_icu,
    CASE WHEN COUNT(is.hadm_id) > 0 THEN 1 ELSE 0 END AS any_icu
  FROM bleed_adm ba
  LEFT JOIN icu_stays is ON ba.hadm_id = is.hadm_id
  GROUP BY 
    ba.subject_id, ba.hadm_id, ba.gender, ba.anchor_age, ba.admittime, 
    ba.dischtime, ba.died, ba.los_days, ba.bleed_type
),
los_bin AS (
  SELECT *,
    CASE 
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9'
      WHEN los_days >= 10 THEN '>=10'
      ELSE 'Other'
    END AS los_bin
  FROM has_icu
)
-- Mortality by bleed_type, los_bin, day1_icu
SELECT 
  'Mortality' AS metric,
  bleed_type,
  los_bin,
  CAST(day1_icu AS STRING) AS day1_icu_status,
  COUNT(*) AS total,
  SUM(died) AS num_died,
  ROUND(SUM(died) * 100.0 / COUNT(*), 2) AS mortality_pct,
  NULL AS icu_num,
  NULL AS icu_rate_pct
FROM los_bin
GROUP BY bleed_type, los_bin, day1_icu

UNION ALL

-- ICU admission rates by bleed_type (overall)
SELECT 
  'ICU Rate' AS metric,
  bleed_type,
  NULL AS los_bin,
  NULL AS day1_icu_status,
  COUNT(*) AS total,
  NULL AS num_died,
  NULL AS mortality_pct,
  SUM(any_icu) AS icu_num,
  ROUND(SUM(any_icu) * 100.0 / COUNT(*), 2) AS icu_rate_pct
FROM los_bin
GROUP BY bleed_type

ORDER BY metric, bleed_type, los_bin, day1_icu_status;