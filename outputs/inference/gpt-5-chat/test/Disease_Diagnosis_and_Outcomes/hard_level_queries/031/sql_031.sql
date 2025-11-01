WITH asthma_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag,
    d_icd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code
    AND diag.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND UPPER(d_icd.long_title) LIKE '%ASTHMA%'
),
comorbidity_scores AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    -- crude score: count of comorbidity categories with weights
    SUM(
      CASE WHEN UPPER(long_title) LIKE '%DIABETES%' THEN 1 ELSE 0 END +
      CASE WHEN UPPER(long_title) LIKE '%HEART%' THEN 2 ELSE 0 END +
      CASE WHEN UPPER(long_title) LIKE '%CANCER%' THEN 2 ELSE 0 END +
      CASE WHEN UPPER(long_title) LIKE '%RENAL%' THEN 2 ELSE 0 END +
      CASE WHEN UPPER(long_title) LIKE '%STROKE%' THEN 2 ELSE 0 END +
      CASE WHEN UPPER(long_title) LIKE '%COPD%' THEN 1 ELSE 0 END
    ) AS risk_score
  FROM asthma_admissions
  GROUP BY subject_id, hadm_id, hospital_expire_flag
),
complications AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.hospital_expire_flag,
    cs.risk_score,
    MAX(CASE WHEN UPPER(d_icd.long_title) LIKE '%MYOCARD%' 
               OR UPPER(d_icd.long_title) LIKE '%INFARCTION%'
               OR UPPER(d_icd.long_title) LIKE '%ARRHYTHMIA%'
               OR UPPER(d_icd.long_title) LIKE '%HEART FAILURE%' 
               OR UPPER(d_icd.long_title) LIKE '%CARDIAC%' 
             THEN 1 ELSE 0 END) AS cardio_flag,
    MAX(CASE WHEN UPPER(d_icd.long_title) LIKE '%STROKE%'
               OR UPPER(d_icd.long_title) LIKE '%HEMORRHAGE%'
               OR UPPER(d_icd.long_title) LIKE '%SEIZURE%'
               OR UPPER(d_icd.long_title) LIKE '%NEURO%' 
             THEN 1 ELSE 0 END) AS neuro_flag
  FROM comorbidity_scores cs
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON cs.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code
    AND diag.icd_version = d_icd.icd_version
  GROUP BY cs.subject_id, cs.hadm_id, cs.hospital_expire_flag, cs.risk_score
),
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    risk_score,
    cardio_flag,
    neuro_flag,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM complications
)
SELECT
  risk_quartile,
  COUNT(*) AS admissions,
  ROUND(AVG(hospital_expire_flag)*100, 1) AS mortality_rate_percent,
  ROUND(AVG(cardio_flag)*100, 1) AS cardiovascular_complication_rate_percent,
  ROUND(AVG(neuro_flag)*100, 1) AS neurologic_complication_rate_percent
FROM quartiles
GROUP BY risk_quartile
ORDER BY risk_quartile;