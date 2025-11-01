WITH pneumonia_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    -- Compute age at admission
    DATE_DIFF(a.admittime, 
              DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                       INTERVAL p.anchor_age YEAR), 
              'YEAR') AS age_at_admission,
    -- Count distinct ICD-10 codes for comorbidity proxy
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'J10%' OR d.icd_code LIKE 'J11%' OR d.icd_code LIKE 'J12%' OR 
         d.icd_code LIKE 'J18%' OR d.icd_code LIKE 'J20%' OR d.icd_code LIKE 'J21%' OR 
         d.icd_code LIKE 'J22%')
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.deathtime, a.hospital_expire_flag, p.gender, age_at_admission
  HAVING age_at_admission BETWEEN 73 AND 83
),
cohort AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY comorbidity_count DESC) AS quartile
  FROM pneumonia_admissions
),
top_quartile AS (
  SELECT *
  FROM cohort
  WHERE quartile = 1
),
mortality_complication AS (
  SELECT
    (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS cohort_in_hospital_mortality_percent,
    (SELECT 
       AVG(CASE WHEN complication_exists THEN 1 ELSE 0 END) * 100.0 
     FROM (
       SELECT 
         t.hadm_id,
         MAX(CASE WHEN d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR 
                    d.icd_code = 'J80.1' OR d.icd_code = 'J96.9' 
                 THEN 1 ELSE 0 END) AS complication_exists
       FROM top_quartile t
       INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
         ON t.hadm_id = d.hadm_id
       GROUP BY t.hadm_id
     )) AS cohort_major_complication_percent
  FROM top_quartile
),
survival AS (
  SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY survival_days) AS cohort_median_survival_days
  FROM (
    SELECT 
      DATE_DIFF(deathtime, admittime, 'DAY') AS survival_days
    FROM top_quartile
    WHERE hospital_expire_flag = 1
  )
)
SELECT 
  m.cohort_in_hospital_mortality_percent,
  m.cohort_major_complication_percent,
  s.cohort_median_survival_days
FROM mortality_complication m, survival s;