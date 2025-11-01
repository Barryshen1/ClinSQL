WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    -- Calculate age at admission: anchor_age + (admission year - anchor_year)
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
asthma_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '493%') OR  -- ICD-9 asthma
    (icd_version = 10 AND icd_code LIKE 'J45%')   -- ICD-10 asthma
),
cohort_asthma AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag
  FROM cohort c
  INNER JOIN asthma_admissions a
    ON c.hadm_id = a.hadm_id
  WHERE c.age_admit BETWEEN 85 AND 95  -- Age filter
),
comorbidity_count AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count  -- Proxy comorbidity score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
complications AS (
  SELECT 
    hadm_id,
    -- Cardiovascular: MI, heart failure, cardiac arrest, stroke
    MAX(CASE 
          WHEN (icd_version = 9 AND (
                  icd_code LIKE '410%' OR  -- MI
                  icd_code LIKE '428%' OR  -- Heart failure
                  icd_code = '427.5' OR    -- Cardiac arrest
                  icd_code BETWEEN '430' AND '434' OR  -- Stroke
                  icd_code BETWEEN '436' AND '437'
                )) 
               OR (icd_version = 10 AND (
                  icd_code LIKE 'I21%' OR  -- MI
                  icd_code LIKE 'I22%' OR
                  icd_code LIKE 'I50%' OR  -- Heart failure
                  icd_code LIKE 'I46%' OR  -- Cardiac arrest
                  icd_code LIKE 'I6%'      -- Stroke (I60-I69)
                )) 
          THEN 1 ELSE 0 
        END) AS cardiovascular_complication,
    -- Neurologic: Stroke, seizures, encephalopathy
    MAX(CASE 
          WHEN (icd_version = 9 AND (
                  icd_code BETWEEN '430' AND '437' OR  -- Stroke
                  icd_code = '780.3' OR               -- Seizures
                  icd_code = '348.3'                  -- Encephalopathy
                )) 
               OR (icd_version = 10 AND (
                  icd_code LIKE 'I6%' OR  -- Stroke
                  icd_code LIKE 'R56%' OR -- Seizures
                  icd_code LIKE 'G93.1%'  -- Encephalopathy
                )) 
          THEN 1 ELSE 0 
        END) AS neurologic_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort_data AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,  -- Handle NULL counts
    COALESCE(cmp.cardiovascular_complication, 0) AS cardiovascular_complication,
    COALESCE(cmp.neurologic_complication, 0) AS neurologic_complication
  FROM cohort_asthma c
  LEFT JOIN comorbidity_count cc
    ON c.hadm_id = cc.hadm_id
  LEFT JOIN complications cmp
    ON c.hadm_id = cmp.hadm_id
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY comorbidity_count) AS comorbidity_quartile
  FROM cohort_data
)
SELECT 
  comorbidity_quartile,
  COUNT(*) AS admissions,
  AVG(1.0 * hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(1.0 * cardiovascular_complication) AS cardiovascular_complication_rate,
  AVG(1.0 * neurologic_complication) AS neurologic_complication_rate
FROM quartiles
GROUP BY comorbidity_quartile
ORDER BY comorbidity_quartile;