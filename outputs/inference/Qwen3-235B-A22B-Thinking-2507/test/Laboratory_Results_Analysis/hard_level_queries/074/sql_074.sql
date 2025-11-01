WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
),

heart_failure_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

cohort AS (
  SELECT 
    ba.hadm_id,
    ba.admittime,
    ba.dischtime,
    ba.hospital_expire_flag
  FROM base_admissions ba
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN heart_failure_codes hfc 
      ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
    WHERE ba.hadm_id = d.hadm_id
  )
),

comparison_group AS (
  SELECT 
    ba.hadm_id,
    ba.admittime,
    ba.dischtime,
    ba.hospital_expire_flag
  FROM base_admissions ba
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN heart_failure_codes hfc 
      ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
    WHERE ba.hadm_id = d.hadm_id
  )
),

critical_labs AS (
  SELECT 
    le.hadm_id,
    le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN base_admissions ba
    ON le.hadm_id = ba.hadm_id
  WHERE 
    le.charttime <= TIMESTAMP_ADD(ba.admittime, INTERVAL 72 HOUR)
    AND le.flag IN ('high', 'low')
),

cohort_lab_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT cl.itemid) AS instability_score
  FROM cohort c
  LEFT JOIN critical_labs cl 
    ON c.hadm_id = cl.hadm_id
  GROUP BY c.hadm_id
),

comparison_lab_scores AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT cl.itemid) AS instability_score
  FROM comparison_group c
  LEFT JOIN critical_labs cl 
    ON c.hadm_id = cl.hadm_id
  GROUP BY c.hadm_id
)

SELECT
  (SELECT MAX(instability_score) FROM cohort_lab_scores) AS max_instability_score,
  (SELECT AVG(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) FROM cohort_lab_scores) AS cohort_critical_event_rate,
  (SELECT AVG(CASE WHEN instability_score > 0 THEN 1 ELSE 0 END) FROM comparison_lab_scores) AS comparison_critical_event_rate,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) FROM cohort) AS avg_los_days,
  (SELECT AVG(hospital_expire_flag) FROM cohort) AS mortality_rate;