WITH population AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  -- Get primary diagnosis
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    -- Filter for age 85-95
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 85 AND 95
    -- Primary diagnosis (seq_num = 1)
    AND d.seq_num = 1
    -- Asthma exacerbation codes
    AND (
      -- ICD-10 codes
      (d.icd_version = 10 AND d.icd_code IN (
        'J45901', 'J45902', 'J45401', 'J45402', 'J45501', 'J45502', 
        'J45201', 'J45202', 'J45101', 'J45102', 'J45001', 'J45002', 'J46'
      ))
      OR
      -- ICD-9 codes
      (d.icd_version = 9 AND d.icd_code IN (
        '49301', '49302', '49311', '49312', '49321', '49322', '49391', '49392'
      ))
    )
),

-- Calculate comorbidity score (simplified Elixhauser)
comorbidity AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.hospital_expire_flag,
    -- Simplified comorbidity score - in reality this would be more comprehensive
    SUM(
      CASE 
        -- Congestive heart failure
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'I50%' THEN 0.683
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4280' AND '4289' THEN 0.683
        -- Cardiac arrhythmias
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'I4%' THEN 0.249
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4260' AND '4279' THEN 0.249
        -- Valvular disease
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'I3%' THEN 0.344
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '3940' AND '3971' THEN 0.344
        -- Peripheral vascular disease
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I71%' OR d.icd_code LIKE 'I73%' OR d.icd_code LIKE 'I74%' OR d.icd_code LIKE 'I77%') THEN 0.129
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4400' AND '4409' THEN 0.129
        -- Hypertension
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'I1%' THEN 0.174
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4010' AND '4059' THEN 0.174
        -- Paralysis
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'G81%' THEN 0.398
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '3420' AND '3449' THEN 0.398
        -- Other neurological disorders
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'G2%' OR d.icd_code LIKE 'G3%' OR d.icd_code LIKE 'G4%' OR d.icd_code LIKE 'G80%' OR d.icd_code LIKE 'G82%' OR d.icd_code LIKE 'G83%') THEN 0.179
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '3300' AND '3359' THEN 0.179
        -- Chronic pulmonary disease
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'J4%' THEN 0.179
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4900' AND '5059' THEN 0.179
        -- Diabetes without complication
        WHEN d.icd_version = 10 AND d.icd_code = 'E119' THEN 0.086
        WHEN d.icd_version = 9 AND d.icd_code = '2500' THEN 0.086
        -- Diabetes with chronic complication
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'E112%' OR d.icd_code LIKE 'E113%' OR d.icd_code LIKE 'E114%') THEN 0.333
        WHEN d.icd_version = 9 AND (d.icd_code = '2502' OR d.icd_code = '2503' OR d.icd_code = '2504') THEN 0.333
        -- Hypothyroidism
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'E0%' THEN 0.037
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '2400' AND '2469' THEN 0.037
        -- Renal failure
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code = 'N19') THEN 0.763
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '5851' AND '5869' THEN 0.763
        -- Liver disease
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'I86%' OR d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K76%') THEN 0.856
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '5700' AND '5739' THEN 0.856
        -- Peptic ulcer disease
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'K25%' THEN 0.065
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '5310' AND '5349' THEN 0.065
        -- AIDS
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'B20%' THEN 1.651
        WHEN d.icd_version = 9 AND d.icd_code = '042' THEN 1.651
        -- Lymphoma
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'C8%' THEN 0.859
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '2000' AND '2023' THEN 0.859
        -- Metastatic cancer
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'C7%' THEN 0.852
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '1960' AND '1991' THEN 0.852
        -- Solid tumor without metastasis
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'C0%' OR d.icd_code LIKE 'C1%' OR d.icd_code LIKE 'C2%' OR d.icd_code LIKE 'C3%' OR d.icd_code LIKE 'C4%' OR d.icd_code LIKE 'C5%' OR d.icd_code LIKE 'C6%' OR d.icd_code LIKE 'C7%' OR d.icd_code LIKE 'C9%' OR d.icd_code LIKE 'D0%' OR d.icd_code LIKE 'D37%' OR d.icd_code LIKE 'D48%') THEN 0.237
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '1400' AND '2390' THEN 0.237
        -- Rheumatoid arthritis
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'M05%' THEN 0.224
        WHEN d.icd_version = 9 AND d.icd_code = '7140' THEN 0.224
        -- Coagulopathy
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'D65%' OR d.icd_code LIKE 'D68%' OR d.icd_code LIKE 'D69%') THEN 0.278
        WHEN d.icd_version = 9 AND (d.icd_code BETWEEN '2860' AND '2869' OR d.icd_code BETWEEN '2870' AND '2875') THEN 0.278
        -- Obesity
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'E66%' THEN 0.046
        WHEN d.icd_version = 9 AND d.icd_code = '2780' THEN 0.046
        -- Weight loss
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'R63%' THEN 0.274
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '7830' AND '7834' THEN 0.274
        -- Fluid and electrolyte disorders
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'E87%' THEN 0.312
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '2760' AND '2769' THEN 0.312
        -- Blood loss anemia
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'D50%' THEN 0.169
        WHEN d.icd_version = 9 AND d.icd_code = '2800' THEN 0.169
        -- Deficiency anemias
        WHEN d.icd_version = 10 AND (d.icd_code LIKE 'D5%' OR d.icd_code LIKE 'D64%') THEN 0.095
        WHEN d.icd_version = 9 AND (d.icd_code BETWEEN '2801' AND '2819') THEN 0.095
        -- Alcohol abuse
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'F10%' THEN 0.071
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '3030' AND '3039' THEN 0.071
        -- Drug abuse
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'F11%' THEN 0.223
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '3040' AND '3059' THEN 0.223
        -- Psychoses
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'F2%' THEN 0.155
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '2950' AND '2999' THEN 0.155
        -- Depression
        WHEN d.icd_version = 10 AND d.icd_code LIKE 'F3%' THEN 0.049
        WHEN d.icd_version = 9 AND d.icd_code BETWEEN '2962' AND '2963' THEN 0.049
        ELSE 0
      END
    ) AS elixhauser_score
  FROM population p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON p.hadm_id = d.hadm_id
  GROUP BY p.subject_id, p.hadm_id, p.hospital_expire_flag
),

-- Identify complications
complications AS (
  SELECT 
    c.*,
    -- Cardiovascular complications (secondary diagnoses)
    MAX(CASE 
      -- Acute MI
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'I21%' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4100' AND '4109' THEN 1
      -- Unstable angina
      WHEN d.icd_version = 10 AND d.icd_code = 'I200' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code = '4111' THEN 1
      -- Cardiac arrest
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'I46%' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code = '4275' THEN 1
      -- Arrhythmia
      WHEN d.icd_version = 10 AND (d.icd_code LIKE 'I44%' OR d.icd_code LIKE 'I45%' OR d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%') THEN 1
      WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4260' AND '4279' THEN 1
      -- Acute heart failure
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'I50%' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4280' AND '4289' THEN 1
      ELSE 0
    END) AS cv_complication,
    
    -- Neurologic complications (secondary diagnoses)
    MAX(CASE 
      -- Stroke
      WHEN d.icd_version = 10 AND (d.icd_code LIKE 'I63%' OR d.icd_code = 'I64') THEN 1
      WHEN d.icd_version = 9 AND d.icd_code BETWEEN '4330' AND '4349' THEN 1
      -- Seizure
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'R56%' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code = '7803' THEN 1
      -- Coma
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'R402%' THEN 1
      WHEN d.icd_version = 9 AND d.icd_code = '7800' THEN 1
      ELSE 0
    END) AS neuro_complication
  FROM comorbidity c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  -- Only consider secondary diagnoses (not the primary asthma diagnosis)
  WHERE d.seq_num > 1
  GROUP BY c.subject_id, c.hadm_id, c.hospital_expire_flag, c.elixhauser_score
),

-- Add quartile information
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY elixhauser_score) AS quartile
  FROM complications
)

-- Final results by quartile
SELECT
  quartile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(cv_complication) AS cv_complication_rate,
  AVG(neuro_complication) AS neuro_complication_rate
FROM quartiles
GROUP BY quartile
ORDER BY quartile;