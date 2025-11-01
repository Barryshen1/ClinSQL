WITH icu_first AS (
  -- Identify first ICU stay per subject
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),

cohort AS (
  -- Base cohort: male, 74-84, first ICU stay, admission with primary upper GI bleed (ICD-10)
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    icu_first i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'K25%' OR d.icd_code = 'K22.6')  -- Upper GI bleed primary codes
),

diagnostic_intensity AS (
  -- Count distinct diagnostic procedures (itemids) in first 72 hours
  SELECT 
    c.subject_id,
    c.stay_id,
    COUNT(DISTINCT ce.itemid) AS procedure_count
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 72 HOUR
    AND di.category IN ('Routine Vital Signs', 'Blood Tests', 'Respiratory', 'Urine Output', 'Labs', 'Procedures')  -- Expanded diagnostic categories
    AND ce.valuenum IS NOT NULL  -- Valid measurements
  GROUP BY 
    c.subject_id, c.stay_id
),

quartiles AS (
  -- Assign quartiles based on procedure count
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM diagnostic_intensity
),

all_patients AS (
  -- Combine with cohort to include zero-procedure patients
  SELECT 
    c.subject_id,
    c.stay_id,
    COALESCE(q.procedure_count, 0) AS procedure_count,
    q.quartile,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM 
    cohort c
  LEFT JOIN 
    quartiles q
    ON c.subject_id = q.subject_id AND c.stay_id = q.stay_id
)

-- Aggregate outcomes by quartile
SELECT 
  quartile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS mean_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT)), 4) AS mean_inhospital_mortality  -- Mortality rate
FROM 
  all_patients
GROUP BY 
  quartile
ORDER BY 
  quartile;