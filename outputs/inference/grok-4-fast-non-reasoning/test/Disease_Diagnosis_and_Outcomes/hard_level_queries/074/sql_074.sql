WITH cohort AS (
  -- Base cohort: males 79-89 with PE
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND d.icd_code LIKE 'I26.%'
    AND d.icd_version = '10'
),

comorbidities AS (
  -- CCI components (full mappings for Charlson Comorbidity Index)
  SELECT 
    c.*,
    -- MI (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND di.icd_code LIKE 'I21%' AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS mi,
    -- CHF (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code IN ('I09.9', 'I11.0', 'I13.0', 'I13.2', 'I25.5') 
             OR di.icd_code LIKE 'I42%' OR di.icd_code LIKE 'I43%' OR di.icd_code LIKE 'I50%') 
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS chf,
    -- Dementia (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'F01%' OR di.icd_code LIKE 'F02%' OR di.icd_code LIKE 'F03%')
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS dementia,
    -- COPD (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'J40%' OR di.icd_code LIKE 'J41%' OR di.icd_code LIKE 'J42%' 
             OR di.icd_code LIKE 'J43%' OR di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J47%')
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS copd,
    -- Diabetes without complications (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'E10.0%' OR di.icd_code LIKE 'E10.1%' OR di.icd_code LIKE 'E10.9%'
             OR di.icd_code LIKE 'E11.0%' OR di.icd_code LIKE 'E11.1%' OR di.icd_code LIKE 'E11.9%'
             OR di.icd_code LIKE 'E12.0%' OR di.icd_code LIKE 'E12.1%' OR di.icd_code LIKE 'E12.9%'
             OR di.icd_code LIKE 'E13.0%' OR di.icd_code LIKE 'E13.1%' OR di.icd_code LIKE 'E13.9%'
             OR di.icd_code LIKE 'E14.0%' OR di.icd_code LIKE 'E14.1%' OR di.icd_code LIKE 'E14.9%')
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS diabetes,
    -- Diabetes with complications (weight 2; overrides above)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'E10.2%' OR di.icd_code LIKE 'E10.3%' OR di.icd_code LIKE 'E10.4%'
             OR di.icd_code LIKE 'E11.2%' OR di.icd_code LIKE 'E11.3%' OR di.icd_code LIKE 'E11.4%'
             OR di.icd_code LIKE 'E12.2%' OR di.icd_code LIKE 'E12.3%' OR di.icd_code LIKE 'E12.4%'
             OR di.icd_code LIKE 'E13.2%' OR di.icd_code LIKE 'E13.3%' OR di.icd_code LIKE 'E13.4%'
             OR di.icd_code LIKE 'E14.2%' OR di.icd_code LIKE 'E14.3%' OR di.icd_code LIKE 'E14.4%')
        AND di.icd_version = '10'
    ) THEN 2 ELSE 0 END AS diabetes_comp,
    -- Vascular disease (weight 1)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'I70%' OR di.icd_code LIKE 'I71%' OR di.icd_code IN ('I73.1', 'I73.8', 'I73.9', 'I77.1', 'K55.1', 'K95.8', 'Z95.9'))
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS vascular,
    -- Renal disease (weight 2)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'I12%' OR di.icd_code LIKE 'I13%' OR di.icd_code LIKE 'N18%' 
             OR di.icd_code LIKE 'N19%' OR di.icd_code LIKE 'N25.1%' OR di.icd_code = 'Z49.2' 
             OR di.icd_code LIKE 'Z99.2%' OR di.icd_code IN ('E10.2', 'E11.2', 'E13.2', 'E14.2'))
        AND di.icd_version = '10'
    ) THEN 2 ELSE 0 END AS renal,
    -- Malignancy (weight 2)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'C00%' OR di.icd_code LIKE 'C01%' OR di.icd_code LIKE 'C02%' OR di.icd_code LIKE 'C03%' OR di.icd_code LIKE 'C04%'
             OR di.icd_code LIKE 'C05%' OR di.icd_code LIKE 'C06%' OR di.icd_code LIKE 'C07%' OR di.icd_code LIKE 'C08%' OR di.icd_code LIKE 'C09%'
             OR di.icd_code LIKE 'C10%' OR di.icd_code LIKE 'C11%' OR di.icd_code LIKE 'C12%' OR di.icd_code LIKE 'C13%' OR di.icd_code LIKE 'C14%'
             OR di.icd_code LIKE 'C15%' OR di.icd_code LIKE 'C16%' OR di.icd_code LIKE 'C17%' OR di.icd_code LIKE 'C18%' OR di.icd_code LIKE 'C19%'
             OR di.icd_code LIKE 'C20%' OR di.icd_code LIKE 'C21%' OR di.icd_code LIKE 'C22%' OR di.icd_code LIKE 'C23%' OR di.icd_code LIKE 'C24%'
             OR di.icd_code LIKE 'C25%' OR di.icd_code LIKE 'C26%' OR di.icd_code LIKE 'C30%' OR di.icd_code LIKE 'C31%' OR di.icd_code LIKE 'C32%'
             OR di.icd_code LIKE 'C33%' OR di.icd_code LIKE 'C34%' OR di.icd_code LIKE 'C35%' OR di.icd_code LIKE 'C36%' OR di.icd_code LIKE 'C37%'
             OR di.icd_code LIKE 'C38%' OR di.icd_code LIKE 'C39%' OR di.icd_code LIKE 'C40%' OR di.icd_code LIKE 'C41%' OR di.icd_code LIKE 'C43%'
             OR di.icd_code LIKE 'C44%' OR di.icd_code LIKE 'C45%' OR di.icd_code LIKE 'C46%' OR di.icd_code LIKE 'C47%' OR di.icd_code LIKE 'C48%'
             OR di.icd_code LIKE 'C49%' OR di.icd_code LIKE 'C50%' OR di.icd_code LIKE 'C51%' OR di.icd_code LIKE 'C52%' OR di.icd_code LIKE 'C53%'
             OR di.icd_code LIKE 'C54%' OR di.icd_code LIKE 'C55%' OR di.icd_code LIKE 'C56%' OR di.icd_code LIKE 'C57%' OR di.icd_code LIKE 'C58%'
             OR di.icd_code LIKE 'C60%' OR di.icd_code LIKE 'C61%' OR di.icd_code LIKE 'C62%' OR di.icd_code LIKE 'C63%' OR di.icd_code LIKE 'C64%'
             OR di.icd_code LIKE 'C65%' OR di.icd_code LIKE 'C66%' OR di.icd_code LIKE 'C67%' OR di.icd_code LIKE 'C68%' OR di.icd_code LIKE 'C69%'
             OR di.icd_code LIKE 'C70%' OR di.icd_code LIKE 'C71%' OR di.icd_code LIKE 'C72%' OR di.icd_code LIKE 'C73%' OR di.icd_code LIKE 'C74%'
             OR di.icd_code LIKE 'C75%' OR di.icd_code LIKE 'C76%' OR di.icd_code LIKE 'C77%' OR di.icd_code LIKE 'C78%' OR di.icd_code LIKE 'C79%'
             OR di.icd_code LIKE 'C80%' OR di.icd_code LIKE 'C81%' OR di.icd_code LIKE 'C82%' OR di.icd_code LIKE 'C83%' OR di.icd_code LIKE 'C84%'
             OR di.icd_code LIKE 'C85%' OR di.icd_code LIKE 'C86%' OR di.icd_code LIKE 'C88%' OR di.icd_code LIKE 'C90%' OR di.icd_code LIKE 'C91%'
             OR di.icd_code LIKE 'C92%' OR di.icd_code LIKE 'C93%' OR di.icd_code LIKE 'C94%' OR di.icd_code LIKE 'C95%' OR di.icd_code LIKE 'C96%'
             OR di.icd_code LIKE 'D00%' OR di.icd_code LIKE 'D01%' OR di.icd_code LIKE 'D02%' OR di.icd_code LIKE 'D03%' OR di.icd_code LIKE 'D04%'
             OR di.icd_code LIKE 'D05%' OR di.icd_code LIKE 'D06%' OR di.icd_code LIKE 'D07%' OR di.icd_code LIKE 'D08%' OR di.icd_code LIKE 'D09%')
        AND di.icd_version = '10'
    ) THEN 2 ELSE 0 END AS malignancy,
    -- Hemiplegia/paraplegia (weight 2)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'G81%' OR di.icd_code LIKE 'G82%' OR di.icd_code LIKE 'G83.0%' OR di.icd_code LIKE 'G83.1%' OR di.icd_code LIKE 'G83.2%'
             OR di.icd_code LIKE 'G83.4%')
        AND di.icd_version = '10'
    ) THEN 2 ELSE 0 END AS hemiplegia,
    -- Liver disease (weight 1 mild; 3 severe - simplified to 1 for basic CCI)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND (di.icd_code LIKE 'B18%' OR di.icd_code IN ('K70.0', 'K70.3', 'K70.9', 'K71.1', 'K71.3', 'K71.4', 'K71.5', 'K71.7', 'K73%', 'K74%',
             'K76.0', 'K76.3', 'K76.4', 'K76.8', 'K76.9', 'Z18.4'))
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS liver,
    -- HIV/AIDS (weight 6)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id 
        AND di.icd_code LIKE 'B20%' OR di.icd_code LIKE 'B21%' OR di.icd_code LIKE 'B22%' OR di.icd_code LIKE 'B24%'
        AND di.icd_version = '10'
    ) THEN 6 ELSE 0 END AS hiv
  FROM cohort c
),

ranked_cohort AS (
  SELECT 
    *,
    -- Compute total_cci as sum of weights (diabetes_comp overrides diabetes)
    (mi + chf + dementia + copd + GREATEST(diabetes, diabetes_comp) + vascular + renal + malignancy + hemiplegia + liver + hiv) AS total_cci,
    PERCENT_RANK() OVER (ORDER BY (mi + chf + dementia + copd + GREATEST(diabetes, diabetes_comp) + vascular + renal + malignancy + hemiplegia + liver + hiv) DESC) AS cci_percentile,
    -- Patient-specific: proxy for 84yo male (filter externally by subject_id/hadm_id for exact)
    CASE WHEN anchor_age = 84 THEN PERCENT_RANK() OVER (ORDER BY (mi + chf + dementia + copd + GREATEST(diabetes, diabetes_comp) + vascular + renal + malignancy + hemiplegia + liver + hiv) DESC) ELSE NULL END AS patient_cci_percentile
  FROM comorbidities
),

outcomes AS (
  SELECT 
    rc.*,
    -- 30-day mortality
    CASE 
      WHEN p.dod IS NOT NULL AND DATE_DIFF(DATE(p.dod), DATE(rc.admittime), DAY) <= 30 THEN 1
      WHEN rc.hospital_expire_flag = 1 THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- Cardiac complications (e.g., ischemia, arrhythmia, heart failure)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = rc.subject_id AND di.hadm_id = rc.hadm_id 
        AND (di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' 
             OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%' OR di.icd_code LIKE 'I30%' 
             OR di.icd_code LIKE 'I31%' OR di.icd_code LIKE 'I32%' OR di.icd_code LIKE 'I33%' 
             OR di.icd_code LIKE 'I34%' OR di.icd_code LIKE 'I35%' OR di.icd_code LIKE 'I36%' 
             OR di.icd_code LIKE 'I37%' OR di.icd_code LIKE 'I38%' OR di.icd_code LIKE 'I40%' 
             OR di.icd_code LIKE 'I41%' OR di.icd_code LIKE 'I42%' OR di.icd_code LIKE 'I43%' 
             OR di.icd_code LIKE 'I44%' OR di.icd_code LIKE 'I45%' OR di.icd_code LIKE 'I46%' 
             OR di.icd_code LIKE 'I47%' OR di.icd_code LIKE 'I48%' OR di.icd_code LIKE 'I49%' 
             OR di.icd_code LIKE 'I50%' OR di.icd_code LIKE 'I51%' OR di.icd_code LIKE 'I52%')
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS cardiac_comp,
    -- Neurologic complications (e.g., stroke, TIA, hemorrhage)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = rc.subject_id AND di.hadm_id = rc.hadm_id 
        AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' 
             OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I67%' OR di.icd_code = 'G45.9')
        AND di.icd_version = '10'
    ) THEN 1 ELSE 0 END AS neuro_comp,
    -- Survival days (to death or discharge; censor at current date for survivors)
    DATE_DIFF(
      COALESCE(DATE(p.dod), COALESCE(DATE(rc.dischtime), CURRENT_DATE())),
      DATE(rc.admittime), 
      DAY
    ) AS survival_days
  FROM ranked_cohort rc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON rc.subject_id = p.subject_id
  WHERE rc.cci_percentile >= 0.75  -- Top quartile (high comorbidity)
)

-- Aggregate for high-comorbidity PE subgroup
SELECT 
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(cardiac_comp) AS cardiac_comp_rate,
  AVG(neuro_comp) AS neuro_comp_rate,
  PERCENTILE_CONT(0.5) OVER (ORDER BY survival_days) AS median_survival_days,
  -- Patient composite risk percentile (from full cohort; filter to specific subject_id/hadm_id externally for exact match)
  MAX(patient_cci_percentile) AS patient_risk_percentile  -- For 84yo males in cohort; may be NULL if no exact match
FROM outcomes;