WITH eligible_asthma AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    -- age at admission: anchor_age + (admit_year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 85 AND 95
    AND d.icd_version = 10
    AND d.icd_code LIKE 'J45%'  -- asthma exacerbation
),

-- 2) All asthma-related diagnoses for those admissions
diag_all AS (
  SELECT e.hadm_id,
         d.icd_code
  FROM eligible_asthma AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.hadm_id = e.hadm_id AND d.subject_id = e.subject_id
  WHERE d.icd_version = 10
),

-- 3) Per-admission comorbidity indicators (proxy for composite comorbidity risk score)
--    We compute presence indicators for a set of common conditions and a simple comorbidity_score
comorbidity AS (
  SELECT
    da.hadm_id,
    -- simple comorbidity score: sum of presence indicators for selected conditions
    (
      MAX(CASE WHEN icd_code LIKE 'E1%' THEN 1 ELSE 0 END) +           -- diabetes (E10-E14)
      MAX(CASE WHEN icd_code LIKE 'J44%' THEN 1 ELSE 0 END) +          -- COPD
      MAX(CASE WHEN icd_code LIKE 'N18%' THEN 1 ELSE 0 END) +          -- CKD
      MAX(CASE WHEN icd_code LIKE 'K70%' OR icd_code LIKE 'K71%' OR icd_code LIKE 'K72%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' OR icd_code LIKE 'K76%' THEN 1 ELSE 0 END) +  -- liver disease
      MAX(CASE WHEN icd_code LIKE 'I10%' OR icd_code LIKE 'I11%' OR icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'I15%' THEN 1 ELSE 0 END) +  -- hypertension
      MAX(CASE WHEN icd_code LIKE 'I50%' THEN 1 ELSE 0 END) +          -- CHF
      MAX(CASE WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1 ELSE 0 END) +  -- MI
      MAX(CASE WHEN icd_code LIKE 'I46%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I48%' OR icd_code LIKE 'I49%' THEN 1 ELSE 0 END) +  -- arrhythmias
      MAX(CASE WHEN icd_code LIKE 'I05%' OR icd_code LIKE 'I06%' OR icd_code LIKE 'I07%' OR icd_code LIKE 'I08%' OR icd_code LIKE 'I09%' THEN 1 ELSE 0 END) +  -- valvular disease
      MAX(CASE WHEN icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' OR icd_code LIKE 'I65%' OR icd_code LIKE 'I66%' OR icd_code LIKE 'I67%' OR icd_code LIKE 'I68%' OR icd_code LIKE 'I69%' THEN 1 ELSE 0 END) +  -- stroke
      MAX(CASE WHEN icd_code LIKE 'F01%' OR icd_code LIKE 'F03%' THEN 1 ELSE 0 END) +  -- dementia
      MAX(CASE WHEN icd_code LIKE 'E66%' THEN 1 ELSE 0 END) +          -- obesity
      MAX(CASE WHEN icd_code LIKE 'I70%' OR icd_code LIKE 'I71%' OR icd_code LIKE 'I72%' OR icd_code LIKE 'I73%' OR icd_code LIKE 'I74%' OR icd_code LIKE 'I75%' THEN 1 ELSE 0 END)  -- peripheral vascular disease
    ) AS comorbidity_score,
    -- cardiovascular complications presence
    MAX(CASE WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I50%' OR icd_code LIKE 'I46%' OR icd_code LIKE 'I47%' OR icd_code LIKE 'I48%' OR icd_code LIKE 'I49%' OR icd_code LIKE 'I05%' OR icd_code LIKE 'I06%' OR icd_code LIKE 'I07%' OR icd_code LIKE 'I08%' OR icd_code LIKE 'I09%' THEN 1 ELSE 0 END) AS has_cv,
    -- neurologic complications presence
    MAX(CASE WHEN icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' OR icd_code LIKE 'I65%' OR icd_code LIKE 'I66%' OR icd_code LIKE 'I67%' OR icd_code LIKE 'I68%' OR icd_code LIKE 'I69%' OR icd_code LIKE 'G40%' OR icd_code LIKE 'G41%' OR icd_code LIKE 'G45%' THEN 1 ELSE 0 END) AS has_neuro
  FROM diag_all AS da
  GROUP BY da.hadm_id
),

-- 4) Join with admissions to get mortality flag
admission_metrics AS (
  SELECT c.hadm_id,
         c.comorbidity_score,
         c.has_cv,
         c.has_neuro,
         a.hospital_expire_flag
  FROM comorbidity AS c
  JOIN eligible_asthma AS e ON e.hadm_id = c.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = c.hadm_id
),

-- 5) Quartile stratification and outcome rates per quartile
quartiled AS (
  SELECT am.*,
         NTILE(4) OVER (ORDER BY comorbidity_score) AS quartile
  FROM admission_metrics AS am
)

SELECT
  quartile,
  COUNT(*) AS n_admissions,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_per_admission,
  AVG(CAST(has_cv AS FLOAT64)) AS cardiovascular_complication_rate,
  AVG(CAST(has_neuro AS FLOAT64)) AS neurologic_complication_rate
FROM quartiled
GROUP BY quartile
ORDER BY quartile;