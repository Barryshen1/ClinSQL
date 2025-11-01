WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')  -- T2DM ICD-10
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%') -- T2DM ICD-9
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')   -- HF ICD-10
          OR (d.icd_version = 10 AND d.icd_code IN ('I51.4', 'I51.5', 'I51.6')) -- HF ICD-10
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')  -- HF ICD-9
        )
    )
),
insulin_orders AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    LOWER(p.drug) AS drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN eligible_patients ep ON p.hadm_id = ep.hadm_id
  WHERE LOWER(p.drug) LIKE '%glargine%'
     OR LOWER(p.drug) LIKE '%detemir%'
     OR LOWER(p.drug) LIKE '%nph%'
     OR LOWER(p.drug) LIKE '%lispro%'
     OR LOWER(p.drug) LIKE '%aspart%'
     OR LOWER(p.drug) LIKE '%regular%'
     OR LOWER(p.drug) LIKE '%sliding scale%'
),
window_flags AS (
  SELECT 
    ep.hadm_id,
    MAX(CASE 
      WHEN io.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
        AND (io.drug LIKE '%glargine%' OR io.drug LIKE '%detemir%' OR io.drug LIKE '%nph%')
      THEN 1 ELSE 0 END) AS basal_first_48h,
    MAX(CASE 
      WHEN io.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
        AND (io.drug LIKE '%lispro%' OR io.drug LIKE '%aspart%' OR io.drug LIKE '%regular%')
      THEN 1 ELSE 0 END) AS bolus_first_48h,
    MAX(CASE 
      WHEN io.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
        AND io.drug LIKE '%sliding scale%'
      THEN 1 ELSE 0 END) AS sliding_first_48h,
    MAX(CASE 
      WHEN io.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime
        AND (io.drug LIKE '%glargine%' OR io.drug LIKE '%detemir%' OR io.drug LIKE '%nph%')
      THEN 1 ELSE 0 END) AS basal_final_12h,
    MAX(CASE 
      WHEN io.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime
        AND (io.drug LIKE '%lispro%' OR io.drug LIKE '%aspart%' OR io.drug LIKE '%regular%')
      THEN 1 ELSE 0 END) AS bolus_final_12h,
    MAX(CASE 
      WHEN io.starttime BETWEEN TIMESTAMP_SUB(ep.dischtime, INTERVAL 12 HOUR) AND ep.dischtime
        AND io.drug LIKE '%sliding scale%'
      THEN 1 ELSE 0 END) AS sliding_final_12h
  FROM eligible_patients ep
  LEFT JOIN insulin_orders io ON ep.hadm_id = io.hadm_id
  GROUP BY ep.hadm_id, ep.admittime, ep.dischtime
)
SELECT 
  ROUND(100.0 * AVG(basal_first_48h), 2) AS pct_basal_first_48h,
  ROUND(100.0 * AVG(bolus_first_48h), 2) AS pct_bolus_first_48h,
  ROUND(100.0 * AVG(basal_first_48h * bolus_first_48h), 2) AS pct_basal_bolus_first_48h,
  ROUND(100.0 * AVG(sliding_first_48h), 2) AS pct_sliding_first_48h,
  ROUND(100.0 * AVG(basal_final_12h), 2) AS pct_basal_final_12h,
  ROUND(100.0 * AVG(bolus_final_12h), 2) AS pct_bolus_final_12h,
  ROUND(100.0 * AVG(basal_final_12h * bolus_final_12h), 2) AS pct_basal_bolus_final_12h,
  ROUND(100.0 * AVG(sliding_final_12h), 2) AS pct_sliding_final_12h,
  ROUND(100.0 * (AVG(basal_final_12h) - AVG(basal_first_48h)), 2) AS net_change_basal,
  ROUND(100.0 * (AVG(bolus_final_12h) - AVG(bolus_first_48h)), 2) AS net_change_bolus,
  ROUND(100.0 * (AVG(basal_final_12h * bolus_final_12h) - AVG(basal_first_48h * bolus_first_48h)), 2) AS net_change_basal_bolus,
  ROUND(100.0 * (AVG(sliding_final_12h) - AVG(sliding_first_48h)), 2) AS net_change_sliding
FROM window_flags;