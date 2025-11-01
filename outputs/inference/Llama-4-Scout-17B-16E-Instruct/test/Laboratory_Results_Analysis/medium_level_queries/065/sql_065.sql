WITH 
  -- Identify troponin T itemid
  troponin_t_item AS (
    SELECT itemid, label
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE label LIKE '%troponin%'
  ),
  
  -- Select relevant patient admissions
  eligible_patients AS (
    SELECT a.subject_id, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 49 AND 59
      AND a.admission_type = 'acute'
  ),
  
  -- Identify AMI admissions
  ami_admissions AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE '410%'
  ),
  
  -- Filter for AMI and first troponin T
  first_troponin AS (
    SELECT le.hadm_id, le.charttime, le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_t_item tti
      ON le.itemid = tti.itemid
    WHERE le.hadm_id IN (SELECT hadm_id FROM eligible_patients)
      AND le.hadm_id IN (SELECT hadm_id FROM ami_admissions)
      AND le.valuenum > 0.04
  )

SELECT 
  APPROX_QUANTILES(valuenum, 1000)[500] AS median,
  APPROX_QUANTILES(valuenum, 1000)[250] AS q1,
  APPROX_QUANTILES(valuenum, 1000)[750] AS q3
FROM first_troponin;