WITH 
-- Get patient demographics and admission data
patient_data AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
),

-- Get medication data
medication_data AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(DISTINCT drug) AS num_drugs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Calculate medication complexity score (proxy: number of unique drugs)
complexity_score AS (
  SELECT 
    pd.subject_id, 
    pd.hadm_id, 
    md.num_drugs
  FROM 
    patient_data pd
  JOIN 
    medication_data md 
      ON pd.subject_id = md.subject_id AND pd.hadm_id = md.hadm_id
  WHERE 
    pd.gender = 'M' 
    AND pd.anchor_age BETWEEN 40 AND 50
    AND pd.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code LIKE '428%'
    )
),

-- Calculate LOS
los_data AS (
  SELECT 
    subject_id, 
    hadm_id, 
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM 
    patient_data
),

-- Combine data
combined_data AS (
  SELECT 
    cs.subject_id, 
    cs.hadm_id, 
    cs.num_drugs,
    ld.los_days,
    CASE 
      WHEN pd.deathtime IS NOT NULL OR pd.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS in_hospital_death
  FROM 
    complexity_score cs
  JOIN 
    los_data ld 
      ON cs.subject_id = ld.subject_id AND cs.hadm_id = ld.hadm_id
  JOIN 
    patient_data pd 
      ON cs.subject_id = pd.subject_id AND cs.hadm_id = pd.hadm_id
),

-- Calculate 30-day readmission
readmission_data AS (
  SELECT 
    subject_id, 
    hadm_id,
    MIN(CASE 
        WHEN TIMESTAMP_DIFF(a.admittime, pd.dischtime, DAY) BETWEEN 0 AND 30 THEN 1 
        ELSE 0 
      END) OVER (PARTITION BY pd.subject_id) AS readmitted_within_30_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    patient_data pd 
      ON a.subject_id = pd.subject_id
  WHERE 
    a.admittime > pd.dischtime
)

-- Final calculation
SELECT 
  quintile,
  patient_count,
  MIN_score,
  MAX_score,
  AVG(mean_los_days) AS mean_los_days,
  AVG(in_hospital_mortality) AS in_hospital_mortality,
  AVG(thirty_day_readmission) AS thirty_day_readmission
FROM (
  SELECT 
    NTILE(5) OVER (ORDER BY num_drugs) AS quintile,
    COUNT(*) AS patient_count,
    MIN(num_drugs) AS MIN_score,
    MAX(num_drugs) AS MAX_score,
    AVG(los_days) AS mean_los_days,
    SUM(in_hospital_death) / COUNT(*) AS in_hospital_mortality,
    COALESCE(SUM(CASE WHEN readmitted_within_30_days = 1 THEN 1 ELSE 0 END) / COUNT(*), 0) AS thirty_day_readmission
  FROM 
    combined_data cd
  LEFT JOIN 
    readmission_data rd 
      ON cd.subject_id = rd.subject_id
  GROUP BY 
    NTILE(5) OVER (ORDER BY num_drugs),
    patient_count,
    MIN_score,
    MAX_score,
    mean_los_days,
    in_hospital_mortality,
    thirty_day_readmission
) 
GROUP BY 
  quintile, 
  patient_count, 
  MIN_score, 
  MAX_score
ORDER BY 
  quintile;