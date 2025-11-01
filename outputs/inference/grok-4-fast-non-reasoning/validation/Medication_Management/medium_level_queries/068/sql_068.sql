WITH cohort AS (
  -- Base cohort: females 83-93
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.hospital_expire_flag = 0
),

t2dm AS (
  -- T2DM diagnoses (ICD-10 E11.*, ICD-9 250.40/41/42 excluding type 1)
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON CAST(di.icd_code AS STRING) = icd.icd_code 
    AND CAST(di.icd_version AS STRING) = CAST(icd.icd_version AS STRING)
  WHERE (CAST(di.icd_version AS STRING) = 'ICD-10' AND CAST(di.icd_code AS STRING) LIKE 'E11%')
     OR (CAST(di.icd_version AS STRING) = 'ICD-9' AND (
       CAST(TRIM(di.icd_code) AS STRING) LIKE '250.40%' 
       OR CAST(TRIM(di.icd_code) AS STRING) LIKE '250.41%' 
       OR CAST(TRIM(di.icd_code) AS STRING) LIKE '250.42%'
     ))
),

hf AS (
  -- HF diagnoses
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON CAST(di.icd_code AS STRING) = icd.icd_code 
    AND CAST(di.icd_version AS STRING) = CAST(icd.icd_version AS STRING)
  WHERE (CAST(di.icd_version AS STRING) = 'ICD-10' 
         AND (CAST(di.icd_code AS STRING) LIKE 'I50%' OR CAST(di.icd_code AS STRING) = 'I11.0'))
     OR (CAST(di.icd_version AS STRING) = 'ICD-9' 
         AND (CAST(TRIM(di.icd_code) AS STRING) LIKE '428%' 
              OR CAST(di.icd_code AS STRING) IN ('402.01','402.11','402.91','404.01','404.03','404.11','404.13','404.91','404.93')))
),

eligible_adms AS (
  -- Combine cohort with diagnoses
  SELECT c.*
  FROM cohort c
  INNER JOIN t2dm t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  INNER JOIN hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),

insulin_orders AS (
  -- All insulin orders with classification
  SELECT 
    ea.subject_id,
    ea.hadm_id,
    ph.pharmacy_id,
    ph.starttime,
    ph.medication,
    ph.route,
    CASE 
      WHEN ph.medication LIKE '%glargine%' OR ph.medication LIKE '%detemir%' OR ph.medication LIKE '%NPH%' OR ph.medication LIKE '%degludec%' THEN 'basal'
      WHEN ph.medication LIKE '%aspart%' OR ph.medication LIKE '%lispro%' OR (ph.medication LIKE '%regular%' AND ph.medication NOT LIKE '%ss%' AND ph.medication NOT LIKE '%scale%') THEN 'bolus'
      WHEN ph.medication LIKE '%ss%' OR ph.medication LIKE '%scale%' OR ph.medication LIKE '%sliding%' THEN 'sliding'
      ELSE NULL 
    END AS regimen_type
  FROM eligible_adms ea
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ea.subject_id = ph.subject_id AND ea.hadm_id = ph.hadm_id
  WHERE ph.medication LIKE '%insulin%'
    AND ph.route IN ('SUBCUTANEOUS', 'IV Drip', 'IV Push')
    AND ph.starttime >= ea.admittime
    AND ph.starttime < ea.dischtime
    AND ph.status = 'Allow'
),

first_initiations AS (
  -- Earliest initiation per type per admission
  SELECT 
    subject_id,
    hadm_id,
    regimen_type,
    MIN(starttime) AS first_starttime
  FROM insulin_orders
  WHERE regimen_type IS NOT NULL
  GROUP BY subject_id, hadm_id, regimen_type
),

adm_regimens AS (
  -- Assign regimens to admissions (first 48h and final 12h)
  SELECT 
    fi.hadm_id,
    ea.admittime,
    ea.dischtime,
    fi.regimen_type,
    fi.first_starttime,
    -- First 48h flag
    CASE WHEN fi.first_starttime <= TIMESTAMP_ADD(ea.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS in_first_48h,
    -- Final 12h flag (LOS in hours)
    CASE 
      WHEN fi.first_starttime > TIMESTAMP_SUB(ea.dischtime, INTERVAL 12 HOUR) 
           AND TIMESTAMP_DIFF(ea.dischtime, ea.admittime, HOUR) >= 12  -- Only if LOS >=12h
      THEN 1 ELSE 0 
    END AS in_final_12h
  FROM first_initiations fi
  INNER JOIN eligible_adms ea ON fi.hadm_id = ea.hadm_id
),

regimen_summary AS (
  -- Pivot to categories per admission/window
  SELECT 
    hadm_id,
    -- First 48h
    MAX(CASE WHEN regimen_type = 'basal' AND in_first_48h = 1 THEN 1 ELSE 0 END) AS basal_first_48h,
    MAX(CASE WHEN regimen_type = 'bolus' AND in_first_48h = 1 THEN 1 ELSE 0 END) AS bolus_first_48h,
    MAX(CASE WHEN regimen_type = 'sliding' AND in_first_48h = 1 THEN 1 ELSE 0 END) AS sliding_first_48h,
    -- Final 12h
    MAX(CASE WHEN regimen_type = 'basal' AND in_final_12h = 1 THEN 1 ELSE 0 END) AS basal_final_12h,
    MAX(CASE WHEN regimen_type = 'bolus' AND in_final_12h = 1 THEN 1 ELSE 0 END) AS bolus_final_12h,
    MAX(CASE WHEN regimen_type = 'sliding' AND in_final_12h = 1 THEN 1 ELSE 0 END) AS sliding_final_12h
  FROM adm_regimens
  GROUP BY hadm_id
),

aggregated_stats AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS total_admissions,
    -- First 48h %
    AVG(basal_first_48h) * 100 AS pct_basal_first_48h,
    AVG(bolus_first_48h) * 100 AS pct_bolus_first_48h,
    AVG(sliding_first_48h) * 100 AS pct_sliding_first_48h,
    -- Basal-bolus as combined (if both basal and bolus)
    AVG(CASE WHEN basal_first_48h = 1 AND bolus_first_48h = 1 THEN 1 ELSE 0 END) * 100 AS pct_basal_bolus_first_48h,
    -- Final 12h %
    AVG(basal_final_12h) * 100 AS pct_basal_final_12h,
    AVG(bolus_final_12h) * 100 AS pct_bolus_final_12h,
    AVG(sliding_final_12h) * 100 AS pct_sliding_final_12h,
    AVG(CASE WHEN basal_final_12h = 1 AND bolus_final_12h = 1 THEN 1 ELSE 0 END) * 100 AS pct_basal_bolus_final_12h
  FROM regimen_summary
)

SELECT 
  total_admissions,
  ROUND(pct_basal_first_48h, 2) AS pct_basal_first_48h,
  ROUND(pct_bolus_first_48h, 2) AS pct_bolus_first_48h,
  ROUND(pct_basal_bolus_first_48h, 2) AS pct_basal_bolus_first_48h,
  ROUND(pct_sliding_first_48h, 2) AS pct_sliding_first_48h,
  ROUND(pct_basal_final_12h, 2) AS pct_basal_final_12h,
  ROUND(pct_bolus_final_12h, 2) AS pct_bolus_final_12h,
  ROUND(pct_basal_bolus_final_12h, 2) AS pct_basal_bolus_final_12h,
  ROUND(pct_sliding_final_12h, 2) AS pct_sliding_final_12h,
  -- Net changes
  ROUND(pct_basal_final_12h - pct_basal_first_48h, 2) AS net_change_basal,
  ROUND(pct_bolus_final_12h - pct_bolus_first_48h, 2) AS net_change_bolus,
  ROUND(pct_basal_bolus_final_12h - pct_basal_bolus_first_48h, 2) AS net_change_basal_bolus,
  ROUND(pct_sliding_final_12h - pct_sliding_first_48h, 2) AS net_change_sliding
FROM aggregated_stats;