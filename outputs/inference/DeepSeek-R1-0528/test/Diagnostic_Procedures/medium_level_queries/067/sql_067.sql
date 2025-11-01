WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admission,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_admissions AS (
  SELECT *
  FROM base_admissions
  WHERE 
    age_admission BETWEEN 39 AND 49
    AND los_days BETWEEN 1 AND 7
),
acs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'acute coronary syndrome|unstable angina|acute myocardial infarction|subsequent myocardial infarction|acute ischemic heart disease')
),
acs_admissions AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN di.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END) AS acs_category
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN acs_codes 
    ON di.icd_code = acs_codes.icd_code 
    AND di.icd_version = acs_codes.icd_version
  GROUP BY di.hadm_id
),
admissions_with_acs AS (
  SELECT 
    f.*,
    a.acs_category
  FROM filtered_admissions f
  INNER JOIN acs_admissions a
    ON f.hadm_id = a.hadm_id
),
us_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE REGEXP_CONTAINS(LOWER(long_title), r'ultrasound|echocardiogram')
),
us_icd AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS us_count_icd
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN us_icd_codes u 
    ON p.icd_code = u.icd_code 
    AND p.icd_version = u.icd_version  -- Fixed missing AND
  INNER JOIN admissions_with_acs a 
    ON p.hadm_id = a.hadm_id
  WHERE 
    p.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
  GROUP BY p.hadm_id
),
us_hcpcs_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_description), r'ultrasound|echocardiogram') OR 
    REGEXP_CONTAINS(LOWER(short_description), r'ultrasound|echocardiogram')
),
us_hcpcs AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS us_count_hcpcs
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN us_hcpcs_codes uh 
    ON h.hcpcs_cd = uh.code
  INNER JOIN admissions_with_acs a 
    ON h.hadm_id = a.hadm_id
  WHERE 
    h.chartdate BETWEEN DATE(a.admittime) AND DATE(a.dischtime)
  GROUP BY h.hadm_id
),
combined_counts AS (
  SELECT 
    a.hadm_id,
    a.acs_category,
    a.los_days,
    COALESCE(ui.us_count_icd, 0) + COALESCE(uh.us_count_hcpcs, 0) AS total_us_count
  FROM admissions_with_acs a
  LEFT JOIN us_icd ui 
    ON a.hadm_id = ui.hadm_id
  LEFT JOIN us_hcpcs uh 
    ON a.hadm_id = uh.hadm_id
),
with_los_group AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM combined_counts
)
SELECT 
  acs_category,
  los_group,
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(total_us_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(total_us_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(total_us_count, 4)[OFFSET(3)] AS p75
FROM with_los_group
GROUP BY acs_category, los_group
ORDER BY acs_category, los_group;