WITH 
ihd_icd_codes AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
  WHERE (icd_version = 10 AND long_title LIKE '%Ischaemic heart disease%') 
  OR (icd_version = 9 AND long_title LIKE '%Ischemic heart disease%')
),
ihd_admissions AS (
  SELECT DISTINCT d.hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code IN (SELECT icd_code FROM ihd_icd_codes)
),
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id 
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 36 AND 46 
  AND a.hadm_id IN (SELECT hadm_id FROM ihd_admissions)
),
troponin_t_measurements AS (
  SELECT l.hadm_id, l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn,
         dli.label
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON l.itemid = dli.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM eligible_patients)
  AND dli.label LIKE '%High Sensitivity Troponin-T%' AND l.valuenum > l.ref_range_upper
),
initial_troponin_t AS (
  SELECT hadm_id, valuenum 
  FROM troponin_t_measurements 
  WHERE rn = 1
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM initial_troponin_t;