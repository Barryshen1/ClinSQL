WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        WHERE di.subject_id = a.subject_id 
          AND di.hadm_id = a.hadm_id 
          AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I50%') 
            OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
          )
      ) THEN 'HF'
      ELSE 'General'
    END AS cohort
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 37 AND 47
),
abnormal_labs AS (
  SELECT DISTINCT 
    le.hadm_id,
    le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN qualifying_admissions qa 
    ON le.hadm_id = qa.hadm_id
  WHERE le.charttime >= qa.admittime
    AND le.charttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
    AND le.valuenum IS NOT NULL
),
scores AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT itemid) AS instability_score,
    1 AS has_critical
  FROM abnormal_labs
  GROUP BY hadm_id
)
SELECT 
  cohort,
  COUNT(*) AS n_admissions,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(CAST(COALESCE(has_critical, 0) AS FLOAT64)) AS critical_event_rate,
  MAX(COALESCE(instability_score, 0)) AS max_instability_score
FROM qualifying_admissions qa
LEFT JOIN scores s 
  ON qa.hadm_id = s.hadm_id
GROUP BY cohort
ORDER BY 
  CASE WHEN cohort = 'HF' THEN 1 ELSE 2 END;