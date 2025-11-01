WITH filtered_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),
echocodes AS (
  SELECT 
    icd_code, 
    icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiography%'
     OR LOWER(long_title) LIKE '%echo%'
),
hosp_echo AS (
  SELECT 
    fa.hadm_id,
    COUNT(DISTINCT CASE WHEN ec.icd_code IS NOT NULL THEN pic.icd_code END) AS num_echo
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pic
    ON fa.hadm_id = pic.hadm_id
  LEFT JOIN echocodes ec
    ON pic.icd_code = ec.icd_code 
    AND pic.icd_version = ec.icd_version
  GROUP BY fa.hadm_id
)
SELECT 
  APPROX_QUANTILES(num_echo, 1000)[OFFSET(250)] AS p25_echo
FROM hosp_echo;