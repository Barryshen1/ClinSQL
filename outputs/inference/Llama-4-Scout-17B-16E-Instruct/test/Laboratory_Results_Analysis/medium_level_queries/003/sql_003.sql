WITH 
  -- Identify high-sensitivity Troponin T lab itemid
  troponin_t_item AS (
    SELECT itemid, label
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%Troponin T%'
  ),
  
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 36 AND 46
  ),
  
  -- Identify ischemic heart disease
  ischemic_heart_disease AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I24%' OR icd_code LIKE 'I25%'
  ),
  
  -- Filter lab events for high-sensitivity Troponin T and above ULN
  troponin_t_labevents AS (
    SELECT le.subject_id, le.hadm_id, le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_t_item tti
    ON le.itemid = tti.itemid
    WHERE le.valuenum > 0  -- Assuming valuenum is used for numeric comparison
  ),
  
  -- Combine conditions
  final_patients AS (
    SELECT poi.subject_id, poi.hadm_id, ihd.hadm_id AS ihd_hadm_id, ttl.valuenum
    FROM patients_of_interest poi
    JOIN ischemic_heart_disease ihd
    ON poi.subject_id = ihd.subject_id AND poi.hadm_id = ihd.hadm_id
    JOIN troponin_t_labevents ttl
    ON poi.subject_id = ttl.subject_id AND poi.hadm_id = ttl.hadm_id
  )

-- Calculate percentiles and min-max directly
SELECT 
  APPROX_QUANTILES(valuenum, 0.25) AS p25,
  APPROX_QUANTILES(valuenum, 0.5) AS p50,
  APPROX_QUANTILES(valuenum, 0.75) AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM final_patients;