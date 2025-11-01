WITH dka_population AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE 
    d.icd_code IN ('E1010', 'E1011', 'E1110', 'E1111', 'E1310', 'E1311')
    AND d.icd_version = 10
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
),

hyperkalemia_drugs AS (
  SELECT 
    p.hadm_id,
    MAX(CASE 
      WHEN LOWER(p.drug) LIKE '%lisinopril%' OR
           LOWER(p.drug) LIKE '%enalapril%' OR
           LOWER(p.drug) LIKE '%ramipril%' OR
           LOWER(p.drug) LIKE '%captopril%' OR
           LOWER(p.drug) LIKE '%benazepril%' OR
           LOWER(p.drug) LIKE '%fosinopril%' OR
           LOWER(p.drug) LIKE '%moexipril%' OR
           LOWER(p.drug) LIKE '%perindopril%' OR
           LOWER(p.drug) LIKE '%quinapril%' OR
           LOWER(p.drug) LIKE '%trandolapril%' OR
           LOWER(p.drug) LIKE '%losartan%' OR
           LOWER(p.drug) LIKE '%valsartan%' OR
           LOWER(p.drug) LIKE '%irbesartan%' OR
           LOWER(p.drug) LIKE '%candesartan%' OR
           LOWER(p.drug) LIKE '%telmisartan%' OR
           LOWER(p.drug) LIKE '%olmesartan%' OR
           LOWER(p.drug) LIKE '%eprosartan%' OR
           LOWER(p.drug) LIKE '%spironolactone%' OR
           LOWER(p.drug) LIKE '%eplerenone%' OR
           LOWER(p.drug) LIKE '%potassium chloride%' OR
           LOWER(p.drug) LIKE '%klor-con%' OR
           LOWER(p.drug) LIKE '%k-dur%' OR
           LOWER(p.drug) LIKE '%trimethoprim%' OR
           LOWER(p.drug) LIKE '%bactrim%' OR
           LOWER(p.drug) LIKE '%septra%'
        THEN 1 ELSE 0 
      END) AS has_hyperkalemia_drug
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.hadm_id = a.hadm_id
  WHERE 
    p.starttime >= a.admittime 
    AND p.starttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY p.hadm_id
),

medication_complexity AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT LOWER(drug)) AS drug_count
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN dka_population dp
    ON p.hadm_id = dp.hadm_id
  WHERE 
    p.starttime >= dp.admittime 
    AND p.starttime <= DATETIME_ADD(dp.admittime, INTERVAL 48 HOUR)
  GROUP BY p.hadm_id
),

population_analysis AS (
  SELECT 
    dp.hadm_id,
    COALESCE(hd.has_hyperkalemia_drug, 0) AS has_hyperkalemia_drug,
    mc.drug_count,
    DATETIME_DIFF(dp.dischtime, dp.admittime, HOUR) / 24.0 AS los_days,
    dp.hospital_expire_flag
  FROM dka_population dp
  LEFT JOIN hyperkalemia_drugs hd 
    ON dp.hadm_id = hd.hadm_id
  LEFT JOIN medication_complexity mc 
    ON dp.hadm_id = mc.hadm_id
),

quartile_analysis AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY drug_count DESC) AS complexity_quartile
  FROM population_analysis
)

-- Group comparison
SELECT 
  has_hyperkalemia_drug,
  AVG(drug_count) AS mean_complexity,
  APPROX_QUANTILES(drug_count, 100)[OFFSET(50)] AS median_complexity,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM population_analysis
GROUP BY has_hyperkalemia_drug

UNION ALL

-- Top complexity quartile report
SELECT 
  2 AS has_hyperkalemia_drug,  -- Using 2 to distinguish from main groups
  AVG(drug_count) AS mean_complexity,
  APPROX_QUANTILES(drug_count, 100)[OFFSET(50)] AS median_complexity,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartile_analysis
WHERE complexity_quartile = 1;