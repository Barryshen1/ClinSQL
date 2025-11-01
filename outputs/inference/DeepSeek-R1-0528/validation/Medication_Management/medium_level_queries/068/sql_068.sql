WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 83 AND 93
    -- T2DM criteria
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND (diag.icd_code LIKE '250.%0' OR diag.icd_code LIKE '250.%2'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        )
    )
    -- HF criteria
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I50%' OR diag.icd_code IN ('I11.0', 'I13.0', 'I13.2')))
        )
    )
),

insulin_classified AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%glargine%' OR 
           LOWER(p.drug) LIKE '%detemir%' OR 
           LOWER(p.drug) LIKE '%degludec%' OR 
           LOWER(p.drug) LIKE '%nph%' OR 
           LOWER(p.drug) LIKE '%insulin isophane%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%aspart%' OR 
           LOWER(p.drug) LIKE '%lispro%' OR 
           LOWER(p.drug) LIKE '%glulisine%' OR 
           LOWER(p.drug) LIKE '%regular insulin%' OR 
           LOWER(p.drug) LIKE '%insulin regular%' THEN 'bolus'
      WHEN LOWER(p.drug) LIKE '%sliding scale%' OR 
           LOWER(p.drug) LIKE '%ssi%' THEN 'sliding'
      ELSE NULL 
    END AS insulin_type
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  -- Pre-filter insulin-related drugs
  WHERE 
    p.drug IS NOT NULL
    AND (LOWER(p.drug) LIKE '%insulin%' OR 
         LOWER(p.drug) LIKE '%sliding%' OR 
         LOWER(p.drug) LIKE '%ssi%')
),

flags AS (
  SELECT 
    hadm_id,
    -- First 48h flags
    MAX(CASE 
          WHEN insulin_type = 'basal' AND starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS basal_48h,
    MAX(CASE 
          WHEN insulin_type = 'bolus' AND starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS bolus_48h,
    MAX(CASE 
          WHEN insulin_type = 'sliding' AND starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
          THEN 1 ELSE 0 
        END) AS sliding_48h,
    -- Final 12h flags
    MAX(CASE 
          WHEN insulin_type = 'basal' AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime 
          THEN 1 ELSE 0 
        END) AS basal_12h,
    MAX(CASE 
          WHEN insulin_type = 'bolus' AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime 
          THEN 1 ELSE 0 
        END) AS bolus_12h,
    MAX(CASE 
          WHEN insulin_type = 'sliding' AND starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime 
          THEN 1 ELSE 0 
        END) AS sliding_12h
  FROM insulin_classified
  GROUP BY hadm_id
),

flags_with_bb AS (
  SELECT 
    hadm_id,
    basal_48h,
    bolus_48h,
    sliding_48h,
    basal_12h,
    bolus_12h,
    sliding_12h,
    -- Basal-bolus: both basal AND bolus in the same window
    CASE WHEN basal_48h = 1 AND bolus_48h = 1 THEN 1 ELSE 0 END AS basal_bolus_48h,
    CASE WHEN basal_12h = 1 AND bolus_12h = 1 THEN 1 ELSE 0 END AS basal_bolus_12h
  FROM flags
)

SELECT 
  COUNT(*) AS total_patients,
  -- First 48h percentages
  ROUND(AVG(basal_48h) * 100, 2) AS pct_48h_basal,
  ROUND(AVG(bolus_48h) * 100, 2) AS pct_48h_bolus,
  ROUND(AVG(basal_bolus_48h) * 100, 2) AS pct_48h_basal_bolus,
  ROUND(AVG(sliding_48h) * 100, 2) AS pct_48h_sliding,
  -- Final 12h percentages
  ROUND(AVG(basal_12h) * 100, 2) AS pct_12h_basal,
  ROUND(AVG(bolus_12h) * 100, 2) AS pct_12h_bolus,
  ROUND(AVG(basal_bolus_12h) * 100, 2) AS pct_12h_basal_bolus,
  ROUND(AVG(sliding_12h) * 100, 2) AS pct_12h_sliding,
  -- Net change (final 12h % - first 48h %)
  ROUND((AVG(basal_12h) - AVG(basal_48h)) * 100, 2) AS net_change_basal,
  ROUND((AVG(bolus_12h) - AVG(bolus_48h)) * 100, 2) AS net_change_bolus,
  ROUND((AVG(basal_bolus_12h) - AVG(basal_bolus_48h)) * 100, 2) AS net_change_basal_bolus,
  ROUND((AVG(sliding_12h) - AVG(sliding_48h)) * 100, 2) AS net_change_sliding
FROM cohort c
LEFT JOIN flags_with_bb f ON c.hadm_id = f.hadm_id;