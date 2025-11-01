WITH eligible_patients AS (
  -- Base cohort: females aged 70-80
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),

admissions_with_pe AS (
  -- Inpatient admissions with primary PE diagnosis (ICD-10 I26*)
  SELECT 
    ep.*,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY ep.subject_id ORDER BY a.admittime) AS rn  -- First PE admission per patient
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ep.subject_id = a.subject_id
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I26%'
  WHERE (ep.dod IS NULL OR ep.dod > a.admittime)
),

pe_cohort AS (
  -- Select first PE admission per patient
  SELECT *
  FROM admissions_with_pe
  WHERE rn = 1
),

comorbidities AS (
  -- Extract comorbidities for risk score (all diagnoses in the PE admission)
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.dod,
    -- Cancer (C00-C97)
    MAX(CASE WHEN di.icd_code LIKE 'C[0-9][0-9]' THEN 1 ELSE 0 END) AS has_cancer,
    -- Heart failure (I50)
    MAX(CASE WHEN di.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf,
    -- Chronic lung disease (J40-J47)
    MAX(CASE WHEN di.icd_code LIKE 'J4[0-7]%' THEN 1 ELSE 0 END) AS has_cld
  FROM pe_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pc.subject_id = di.subject_id
    AND pc.hadm_id = di.hadm_id
    AND di.icd_version = '10'
  GROUP BY pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, pc.dod
),

prior_admission AS (
  -- Check for hospitalization in prior 30 days (any cause)
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` prev_a
        WHERE prev_a.subject_id = c.subject_id
          AND prev_a.admittime < c.admittime
          AND prev_a.admittime >= DATE_SUB(c.admittime, INTERVAL 30 DAY)
          AND prev_a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
      ) THEN 1 ELSE 0 
    END AS prior_hosp
  FROM comorbidities c
),

risk_scores AS (
  -- Calculate simplified PESI score
  SELECT 
    *,
    -- Base: age (10 for >=80, but all <=80 so 0 extra; female=0)
    0 AS age_score,
    -- Comorbidities
    (CASE WHEN has_cancer = 1 THEN 30 ELSE 0 END) AS cancer_score,
    (CASE WHEN has_hf = 1 THEN 10 ELSE 0 END) AS hf_score,
    (CASE WHEN has_cld = 1 THEN 10 ELSE 0 END) AS cld_score,
    (CASE WHEN prior_hosp = 1 THEN 20 ELSE 0 END) AS prior_score,
    -- Total
    (CASE WHEN has_cancer = 1 THEN 30 ELSE 0 END) +
    (CASE WHEN has_hf = 1 THEN 10 ELSE 0 END) +
    (CASE WHEN has_cld = 1 THEN 10 ELSE 0 END) +
    (CASE WHEN prior_hosp = 1 THEN 20 ELSE 0 END) AS pesi_score
  FROM prior_admission
),

quintiles AS (
  -- Assign risk quintiles
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY pesi_score) AS risk_quintile
  FROM risk_scores
),

outcomes AS (
  -- Calculate outcomes including AKI/ARDS
  SELECT 
    q.*,
    -- 90-day mortality
    CASE WHEN q.dod IS NOT NULL AND q.dod <= DATE_ADD(q.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END AS mortality_90d,
    -- AKI (N17.* any seq_num)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` aki_d
      WHERE aki_d.subject_id = q.subject_id
        AND aki_d.hadm_id = q.hadm_id
        AND aki_d.icd_version = '10'
        AND aki_d.icd_code LIKE 'N17%'
    ) THEN 1 ELSE 0 END AS aki,
    -- ARDS (J96.0* any seq_num)
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ards_d
      WHERE ards_d.subject_id = q.subject_id
        AND ards_d.hadm_id = q.hadm_id
        AND ards_d.icd_version = '10'
        AND ards_d.icd_code LIKE 'J96.0%'
    ) THEN 1 ELSE 0 END AS ards,
    -- LOS for survivors
    CASE 
      WHEN q.dod IS NULL OR q.dod > DATE_ADD(q.admittime, INTERVAL 90 DAY) 
      THEN EXTRACT(DAY FROM (q.dischtime - q.admittime))
      ELSE NULL 
    END AS survivor_los
  FROM quintiles q
),

general_mortality AS (
  -- Comparison: 90-day mortality for general 70-80 female inpatients (no PE filter)
  SELECT 
    AVG(CASE 
      WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(a.admittime, INTERVAL 90 DAY) THEN 1.0 
      ELSE 0.0 
    END) * 100.0 AS general_mort_rate
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ep.subject_id = a.subject_id
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
  WHERE (ep.dod IS NULL OR ep.dod > a.admittime)
)

-- Final aggregation by quintile
SELECT 
  risk_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(mortality_90d) * 100.0, 2) AS pe_mortality_90d_pct,
  ROUND((SELECT general_mort_rate FROM general_mortality), 2) AS general_mort_70_80f_pct,
  ROUND(AVG(aki) * 100.0, 2) AS aki_rate_pct,
  ROUND(AVG(ards) * 100.0, 2) AS ards_rate_pct,
  ROUND(PERCENTILE_CONT(0.5) OVER (ORDER BY survivor_los), 2) AS median_los_days
FROM outcomes
GROUP BY risk_quintile
ORDER BY risk_quintile;