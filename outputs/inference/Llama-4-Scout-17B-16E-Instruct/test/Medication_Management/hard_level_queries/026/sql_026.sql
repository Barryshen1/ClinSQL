WITH 
-- Identify pneumonia patients
pneumonia_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE dd.long_title LIKE '%Pneumonia%' 
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admit_provider_id IS NOT NULL  -- Ensure we have admitting provider
),

-- Calculate medication complexity (unique drugs in first 7 days)
medication_complexity AS (
  SELECT 
    pp.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs
  FROM pneumonia_patients pp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pp.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN pp.admittime AND TIMESTAMP_ADD(pp.admittime, INTERVAL 7 DAY)
  GROUP BY pp.hadm_id
),

-- Calculate LOS, in-hospital mortality, and 30-day readmission
admission_outcomes AS (
  SELECT 
    mc.hadm_id,
    mc.unique_drugs,
    ao.dischtime,
    ao.admittime,
    ao.hospital_expire_flag,
    TIMESTAMP_DIFF(ao.dischtime, ao.admittime, DAY) AS los_days
  FROM medication_complexity mc
  JOIN pneumonia_patients ao ON mc.hadm_id = ao.hadm_id
),

-- Tertile calculation
tertiles AS (
  SELECT 
    hadm_id,
    unique_drugs,
    NTILE(3) OVER (ORDER BY unique_drugs) AS tertile
  FROM medication_complexity
),

-- 30-day readmission calculation
readmissions AS (
  SELECT 
    a1.hadm_id AS index_hadm_id,
    COUNT(DISTINCT a2.subject_id) AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE a1.dischtime IS NOT NULL 
    AND a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.hadm_id
)

-- Final aggregation
SELECT 
  t.tertile,
  COUNT(*) AS count,
  MIN(t.unique_drugs) AS min_score,
  AVG(t.unique_drugs) AS avg_score,
  MAX(t.unique_drugs) AS max_score,
  AVG(ao.los_days) AS mean_los,
  SUM(CASE WHEN ao.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS in_hospital_mortality_pct,
  COALESCE(r.readmitted / COUNT(DISTINCT t.hadm_id), 0) * 100 AS thirty_day_readmission_pct
FROM tertiles t
JOIN admission_outcomes ao ON t.hadm_id = ao.hadm_id
LEFT JOIN readmissions r ON t.hadm_id = r.index_hadm_id
GROUP BY t.tertile, r.readmitted;