WITH tia_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '435%') 
    OR (icd_version = 10 AND icd_code LIKE 'G45%')
),
base_adm AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    (CAST(EXTRACT(YEAR FROM adm.admittime) AS INT) - (pat.anchor_year - pat.anchor_age)) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND adm.hadm_id IN (SELECT hadm_id FROM tia_admissions)
),
filtered_adm AS (
  SELECT 
    hadm_id,
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los_days
  FROM base_adm
  WHERE age_admit BETWEEN 44 AND 54
),
adm_with_los_group AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group
  FROM filtered_adm
  WHERE los_days BETWEEN 1 AND 7
),
icu_use AS (
  SELECT 
    adm.hadm_id,
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_used
  FROM adm_with_los_group adm
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  GROUP BY adm.hadm_id
),
imaging_events AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
  WHERE 
    REGEXP_CONTAINS(LOWER(dicd.long_title), r'ct|mri|x\-ray|x ray|ultrasound|echo|doppler|angiogram|mammogram|scan|fluoroscopy|dexa|bone density')
  
  UNION ALL
  
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON hc.hcpcs_cd = dh.code
  WHERE 
    REGEXP_CONTAINS(LOWER(dh.long_description), r'ct|mri|x\-ray|x ray|ultrasound|echo|doppler|angiogram|mammogram|scan|fluoroscopy|dexa|bone density')
),
imaging_count_per_adm AS (
  SELECT hadm_id, COUNT(*) AS imaging_count
  FROM imaging_events
  GROUP BY hadm_id
),
adm_combined AS (
  SELECT 
    adm.hadm_id,
    adm.los_group,
    icu.icu_used,
    COALESCE(img.imaging_count, 0) AS imaging_count
  FROM adm_with_los_group adm
  INNER JOIN icu_use icu
    ON adm.hadm_id = icu.hadm_id
  LEFT JOIN imaging_count_per_adm img
    ON adm.hadm_id = img.hadm_id
)
SELECT 
  los_group,
  icu_used,
  approx_quantiles[OFFSET(1)] AS p25,
  approx_quantiles[OFFSET(2)] AS p50,
  approx_quantiles[OFFSET(3)] AS p75
FROM (
  SELECT 
    los_group,
    icu_used,
    APPROX_QUANTILES(imaging_count, 4) AS approx_quantiles
  FROM adm_combined
  GROUP BY los_group, icu_used
)
ORDER BY los_group, icu_used;