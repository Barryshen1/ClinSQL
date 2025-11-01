WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '493.%') OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'J45%' OR d.icd_code = 'J46'))
    )
),
ages AS (
  SELECT c.*, p.anchor_age + EXTRACT(YEAR FROM c.admittime) - 2008 AS age
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON c.subject_id = p.subject_id
  WHERE p.anchor_age + EXTRACT(YEAR FROM c.admittime) - 2008 BETWEEN 85 AND 95
),
comorbid AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    MAX(CASE WHEN d.seq_num > 1 AND (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '428%' OR 
        d.icd_code LIKE '427%' OR d.icd_code = '785.5' OR d.icd_code LIKE '415.1%' OR 
        d.icd_code LIKE '785.51'
      )) OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I21%' OR d.icd_code = 'I20.0' OR d.icd_code LIKE 'I50%' OR 
        d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%' OR 
        d.icd_code LIKE 'R57%' OR d.icd_code LIKE 'I26%' OR d.icd_code LIKE 'I46%'
      ))
    ) THEN 1 ELSE 0 END) AS has_cv_comp,
    MAX(CASE WHEN d.seq_num > 1 AND (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR 
        d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%' OR 
        d.icd_code LIKE '437%' OR d.icd_code LIKE '345%' OR d.icd_code = '293.0' OR 
        d.icd_code = '293.1' OR d.icd_code = '348.3'
      )) OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code = 'G45.9' OR 
        d.icd_code = 'F05' OR d.icd_code LIKE 'G40%' OR d.icd_code LIKE 'G41%' OR 
        d.icd_code = 'G93.4' OR d.icd_code LIKE 'R40.2'
      ))
    ) THEN 1 ELSE 0 END) AS has_neuro_comp,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '410.%') OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I25.2%'))
    ) THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
      (d.icd_version = 10 AND (
        d.icd_code = 'I09.9' OR d.icd_code = 'I11.0' OR d.icd_code LIKE 'I13%' OR 
        d.icd_code LIKE 'I25.5' OR d.icd_code LIKE 'I42%' OR d.icd_code LIKE 'I43%' OR 
        d.icd_code LIKE 'I50%'
      ))
    ) THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR 
        d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'
      ))
    ) THEN 1 ELSE 0 END) AS dm,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND (d.icd_code LIKE '582%' OR d.icd_code LIKE '585%' OR d.icd_code = '586' OR d.icd_code LIKE '588.8')) OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code = 'N19' OR d.icd_code = 'I12.0'))
    ) THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '14%' OR d.icd_code LIKE '15%' OR d.icd_code LIKE '16%' OR 
        d.icd_code LIKE '17%' OR d.icd_code LIKE '18%' OR d.icd_code LIKE '19%' OR 
        d.icd_code LIKE '20%'
      )) OR
      (d.icd_version = 10 AND d.icd_code LIKE 'C%' AND NOT d.icd_code LIKE 'C44%')
    ) THEN 1 ELSE 0 END) AS cancer,
    MAX(CASE WHEN (
      (d.icd_version = 9 AND (d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199.0%' OR d.icd_code LIKE '199.1%')) OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%'))
    ) THEN 1 ELSE 0 END) AS metastatic
  FROM ages
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ages.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id, a.hospital_expire_flag
),
scores AS (
  SELECT 
    hadm_id, 
    hospital_expire_flag, 
    has_cv_comp, 
    has_neuro_comp,
    (COALESCE(mi, 0) * 1 + COALESCE(chf, 0) * 1 + COALESCE(dm, 0) * 1 + 
     COALESCE(renal, 0) * 2 + COALESCE(cancer, 0) * 2 + COALESCE(metastatic, 0) * 3) + 6 AS cci_score
  FROM comorbid
)
SELECT 
  quartile,
  COUNT(*) AS num_admissions,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_percent,
  ROUND(AVG(CAST(COALESCE(has_cv_comp, 0) AS FLOAT64)) * 100, 2) AS cv_complication_rate_percent,
  ROUND(AVG(CAST(COALESCE(has_neuro_comp, 0) AS FLOAT64)) * 100, 2) AS neuro_complication_rate_percent
FROM (
  SELECT *, NTILE(4) OVER (ORDER BY cci_score ASC) AS quartile
  FROM scores
)
GROUP BY quartile
ORDER BY quartile;