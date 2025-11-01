WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    -- Filter for age 40-50
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 40 AND 50
    -- Neutropenic fever: must have both fever and neutropenia ICD codes
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'R50%' AND icd_version = 10
    )
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code = 'D70' AND icd_version = 10
    )
),

-- Compute medication complexity score (distinct meds in first 48h)
med_score AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

-- Assign quartiles based on complexity_score
quartiles AS (
  SELECT 
    hadm_id,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM med_score
),

-- Add next admission time for readmission calculation
cohort_with_next AS (
  SELECT 
    c.*,
    LEAD(admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) AS next_admittime
  FROM cohort c
),

-- Combine all data for final aggregation
base AS (
  SELECT 
    c.hadm_id,
    q.complexity_score,
    q.quartile,
    -- Length of stay in days
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    -- Mortality flag (1 if died in hospital)
    c.hospital_expire_flag AS mortality_flag,
    -- Readmission flag (1 if next admission within 30 days of discharge)
    CASE 
      WHEN DATE(c.next_admittime) <= DATE_ADD(DATE(c.dischtime), INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS readmission_flag
  FROM cohort_with_next c
  INNER JOIN quartiles q 
    ON c.hadm_id = q.hadm_id
)

-- Final output: aggregate by quartile
SELECT 
  quartile,
  COUNT(hadm_id) AS patient_count,
  AVG(complexity_score) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  AVG(los_days) AS mean_los,
  AVG(mortality_flag) * 100 AS mortality_pct,
  AVG(readmission_flag) * 100 AS readmission_30d_pct
FROM base
GROUP BY quartile
ORDER BY quartile;