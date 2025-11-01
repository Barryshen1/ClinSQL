WITH ihd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 
         AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' 
              OR icd_code LIKE 'I23%' OR icd_code LIKE 'I24%' OR icd_code LIKE 'I25%'))
     OR (icd_version = 9 
         AND (icd_code LIKE '410%' OR icd_code LIKE '411%' OR icd_code LIKE '412%' 
              OR icd_code LIKE '413%' OR icd_code LIKE '414%')))
,
copd AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'J44%')
     OR (icd_version = 9 
         AND (icd_code LIKE '490%' OR icd_code LIKE '491%' OR icd_code LIKE '492%' 
              OR icd_code LIKE '494%' OR icd_code LIKE '496%'))
)
SELECT 
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 
    100
  )[OFFSET(75)] AS p75_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON a.subject_id = p.subject_id
INNER JOIN ihd 
  ON a.hadm_id = ihd.hadm_id
INNER JOIN copd 
  ON a.hadm_id = copd.hadm_id
WHERE p.gender = 'M'
  AND FLOOR(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
  AND a.dischtime > a.admittime;