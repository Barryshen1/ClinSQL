WITH index_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
cohort AS (
  SELECT 
    ia.*
  FROM index_admissions ia
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE d.subject_id = ia.subject_id
      AND d.hadm_id = ia.hadm_id
      AND ( 
        (d.icd_version = 9 AND d.icd_code LIKE 'E11%') 
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
      )
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE d.subject_id = ia.subject_id
      AND d.hadm_id = ia.hadm_id
      AND LOWER(dd.long_title) LIKE '%heart failure%'
  )
),
insulin_orders AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    CASE 
      WHEN LOWER(drug) LIKE '%glargine%' OR LOWER(drug) LIKE '%detemir%' OR LOWER(drug) LIKE '%degludec%' 
           OR LOWER(drug) LIKE '%nph%' OR LOWER(drug) LIKE '%ultralente%' OR LOWER(drug) LIKE '%lente%' 
           OR LOWER(drug) LIKE '%insulin zinc%' OR LOWER(drug) LIKE '%insulin protamine%' THEN 'basal'
      WHEN LOWER(drug) LIKE '%aspart%' OR LOWER(drug) LIKE '%lispro%' OR LOWER(drug) LIKE '%glulisine%' 
           OR LOWER(drug) LIKE '%regular insulin%' OR LOWER(drug) LIKE '%semilente%' 
           OR LOWER(drug) LIKE '%rapid-acting%' OR LOWER(drug) LIKE '%short-acting%' THEN 'bolus'
      WHEN LOWER(drug) LIKE '%sliding scale%' OR LOWER(drug) LIKE '%sliding-scale%' 
           OR LOWER(drug) LIKE '%correction scale%' OR LOWER(drug) LIKE '%correction-scale%' THEN 'sliding_scale'
      WHEN LOWER(drug) LIKE '%basal-bolus%' OR LOWER(drug) LIKE '%basal bolus%' THEN 'basal_bolus'
      ELSE NULL
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
),
patient_insulin_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN io.insulin_type = 'basal' 
             AND io.starttime BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 48 HOUR, c.dischtime) 
             THEN 1 ELSE 0 END) AS basal_first,
    MAX(CASE WHEN io.insulin_type = 'bolus' 
             AND io.starttime BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 48 HOUR, c.dischtime) 
             THEN 1 ELSE 0 END) AS bolus_first,
    MAX(CASE WHEN io.insulin_type = 'sliding_scale' 
             AND io.starttime BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 48 HOUR, c.dischtime) 
             THEN 1 ELSE 0 END) AS sliding_scale_first,
    MAX(CASE WHEN io.insulin_type = 'basal_bolus' 
             AND io.starttime BETWEEN c.admittime AND LEAST(c.admittime + INTERVAL 48 HOUR, c.dischtime) 
             THEN 1 ELSE 0 END) AS basal_bolus_first,
    MAX(CASE WHEN io.insulin_type = 'basal' 
             AND io.starttime BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime 
             THEN 1 ELSE 0 END) AS basal_final,
    MAX(CASE WHEN io.insulin_type = 'bolus' 
             AND io.starttime BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime 
             THEN 1 ELSE 0 END) AS bolus_final,
    MAX(CASE WHEN io.insulin_type = 'sliding_scale' 
             AND io.starttime BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime 
             THEN 1 ELSE 0 END) AS sliding_scale_final,
    MAX(CASE WHEN io.insulin_type = 'basal_bolus' 
             AND io.starttime BETWEEN GREATEST(c.admittime, c.dischtime - INTERVAL 12 HOUR) AND c.dischtime 
             THEN 1 ELSE 0 END) AS basal_bolus_final
  FROM cohort c
  LEFT JOIN insulin_orders io 
    ON c.subject_id = io.subject_id AND c.hadm_id = io.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
summary AS (
  SELECT 
    AVG(basal_first) AS pct_basal_first,
    AVG(bolus_first) AS pct_bolus_first,
    AVG(sliding_scale_first) AS pct_sliding_scale_first,
    AVG(basal_bolus_first) AS pct_basal_bolus_first,
    AVG(basal_final) AS pct_basal_final,
    AVG(bolus_final) AS pct_bolus_final,
    AVG(sliding_scale_final) AS pct_sliding_scale_final,
    AVG(basal_bolus_final) AS pct_basal_bolus_final
  FROM patient_insulin_flags
)
SELECT 
  'basal' AS insulin_type,
  pct_basal_first AS pct_first_48h,
  pct_basal_final AS pct_final_12h,
  (pct_basal_final - pct_basal_first) AS net_change
FROM summary
UNION ALL
SELECT 
  'bolus',
  pct_bolus_first,
  pct_bolus_final,
  (pct_bolus_final - pct_bolus_first)
FROM summary
UNION ALL
SELECT 
  'sliding_scale',
  pct_sliding_scale_first,
  pct_sliding_scale_final,
  (pct_sliding_scale_final - pct_sliding_scale_first)
FROM summary
UNION ALL
SELECT 
  'basal_bolus',
  pct_basal_bolus_first,
  pct_basal_bolus_final,
  (pct_basal_bolus_final - pct_basal_bolus_first)
FROM summary;