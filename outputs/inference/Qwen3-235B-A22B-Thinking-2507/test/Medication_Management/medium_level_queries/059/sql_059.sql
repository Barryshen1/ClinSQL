WITH patient_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 60 AND 70
    AND a.dischtime IS NOT NULL  -- Ensure we have discharge time
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          -- T2DM ICD-9 codes (250.x0 or 250.x1 where x is 0, 3, 8, or 9)
          (d.icd_version = 9 AND (d.icd_code LIKE '250.0%' OR d.icd_code LIKE '250.3%' OR 
                                 d.icd_code LIKE '250.8%' OR d.icd_code LIKE '250.9%'))
          OR
          -- T2DM ICD-10 codes (E11.*)
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          -- HF ICD-9 codes (428.*)
          (d.icd_version = 9 AND d.icd_code LIKE '428.%')
          OR
          -- HF ICD-10 codes (I50.*)
          (d.icd_version = 10 AND d.icd_code LIKE 'I50.%')
        )
    )
),

medication_initiation AS (
  SELECT 
    pc.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    
    -- Antidiabetics
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' 
            OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%pioglitazone%'
          THEN p.starttime 
        END) AS first_antidiabetic_time,
    
    -- Beta-blockers
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%bisoprolol%' 
            OR LOWER(p.drug) LIKE '%atenolol%' OR LOWER(p.drug) LIKE '%propranolol%'
          THEN p.starttime 
        END) AS first_beta_blocker_time,
    
    -- ACEi/ARB/ARNI
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%ramipril%' 
            OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' OR LOWER(p.drug) LIKE '%candesartan%'
            OR LOWER(p.drug) LIKE '%sacubitril%' -- ARNI
          THEN p.starttime 
        END) AS first_ace_arb_arni_time,
    
    -- Loop diuretics
    MIN(CASE 
          WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%'
          THEN p.starttime 
        END) AS first_loop_diuretic_time
  
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON pc.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON a.hadm_id = p.hadm_id
  GROUP BY pc.subject_id, a.hadm_id, a.admittime, a.dischtime
),

initiation_windows AS (
  SELECT
    subject_id,
    hadm_id,
    
    -- First 48h window: medication initiated within first 48 hours of admission
    CASE WHEN first_antidiabetic_time IS NOT NULL AND 
              first_antidiabetic_time <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
         THEN 1 ELSE 0 END AS antidiabetic_first_48h,
    CASE WHEN first_beta_blocker_time IS NOT NULL AND 
              first_beta_blocker_time <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
         THEN 1 ELSE 0 END AS beta_blocker_first_48h,
    CASE WHEN first_ace_arb_arni_time IS NOT NULL AND 
              first_ace_arb_arni_time <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
         THEN 1 ELSE 0 END AS ace_arb_arni_first_48h,
    CASE WHEN first_loop_diuretic_time IS NOT NULL AND 
              first_loop_diuretic_time <= TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) 
         THEN 1 ELSE 0 END AS loop_diuretic_first_48h,
    
    -- Final 24h window: medication initiated in the last 24 hours before discharge
    CASE WHEN first_antidiabetic_time IS NOT NULL AND 
              first_antidiabetic_time >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND
              first_antidiabetic_time <= dischtime
         THEN 1 ELSE 0 END AS antidiabetic_final_24h,
    CASE WHEN first_beta_blocker_time IS NOT NULL AND 
              first_beta_blocker_time >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND
              first_beta_blocker_time <= dischtime
         THEN 1 ELSE 0 END AS beta_blocker_final_24h,
    CASE WHEN first_ace_arb_arni_time IS NOT NULL AND 
              first_ace_arb_arni_time >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND
              first_ace_arb_arni_time <= dischtime
         THEN 1 ELSE 0 END AS ace_arb_arni_final_24h,
    CASE WHEN first_loop_diuretic_time IS NOT NULL AND 
              first_loop_diuretic_time >= TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND
              first_loop_diuretic_time <= dischtime
         THEN 1 ELSE 0 END AS loop_diuretic_final_24h
  
  FROM medication_initiation
)

SELECT
  'Antidiabetics' AS medication_class,
  AVG(antidiabetic_first_48h) * 100 AS first_48h_pct,
  AVG(antidiabetic_final_24h) * 100 AS final_24h_pct,
  (AVG(antidiabetic_final_24h) - AVG(antidiabetic_first_48h)) * 100 AS abs_diff_pct
FROM initiation_windows

UNION ALL

SELECT
  'Beta-blockers' AS medication_class,
  AVG(beta_blocker_first_48h) * 100 AS first_48h_pct,
  AVG(beta_blocker_final_24h) * 100 AS final_24h_pct,
  (AVG(beta_blocker_final_24h) - AVG(beta_blocker_first_48h)) * 100 AS abs_diff_pct
FROM initiation_windows

UNION ALL

SELECT
  'ACEi/ARB/ARNI' AS medication_class,
  AVG(ace_arb_arni_first_48h) * 100 AS first_48h_pct,
  AVG(ace_arb_arni_final_24h) * 100 AS final_24h_pct,
  (AVG(ace_arb_arni_final_24h) - AVG(ace_arb_arni_first_48h)) * 100 AS abs_diff_pct
FROM initiation_windows

UNION ALL

SELECT
  'Loop diuretics' AS medication_class,
  AVG(loop_diuretic_first_48h) * 100 AS first_48h_pct,
  AVG(loop_diuretic_final_24h) * 100 AS final_24h_pct,
  (AVG(loop_diuretic_final_24h) - AVG(loop_diuretic_first_48h)) * 100 AS abs_diff_pct
FROM initiation_windows;