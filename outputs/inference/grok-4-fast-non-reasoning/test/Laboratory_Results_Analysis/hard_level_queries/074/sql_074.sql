WITH heart_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE 'I50%' OR icd_code LIKE '428%'
),
hf_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND p.anchor_age > 18  -- Exclude pediatrics
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')  -- Inpatients only
    AND a.dischtime > a.admittime  -- Valid stays
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  HAVING MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM heart_failure_codes) THEN 1 ELSE 0 END) = 1  -- At least one HF dx per hadm
),
general_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND p.anchor_age > 18  -- Exclude pediatrics
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')  -- Inpatients only
    AND a.dischtime > a.admittime  -- Valid stays
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  HAVING MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM heart_failure_codes) THEN 1 ELSE 0 END) = 0  -- No HF dx per hadm
),
cohort AS (
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag, 1 AS hf_flag FROM hf_cohort
  UNION ALL
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag, 0 AS hf_flag FROM general_cohort
),
lab_abnormals AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON l.itemid = li.itemid
  INNER JOIN cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE li.category IN ('Chemistry', 'Hematology', 'Blood Gas', 'Urinalysis')
    AND l.charttime >= c.admittime 
    AND l.charttime <= DATE_ADD(c.admittime, INTERVAL 3 DAY)
    AND l.valuenum IS NOT NULL
    AND (
      (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) OR 
      (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
    )
),
instability_scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.hf_flag,
    COUNT(DISTINCT la.itemid) AS instability_score,
    EXTRACT(DAY FROM (c.dischtime - c.admittime)) AS los_days,
    CASE WHEN c.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END AS mortality
  FROM cohort c
  LEFT JOIN lab_abnormals la 
    ON c.subject_id = la.subject_id AND c.hadm_id = la.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.hf_flag, c.dischtime, c.admittime, c.hospital_expire_flag
),
max_scores AS (
  SELECT 
    hf_flag,
    MAX(instability_score) AS max_instability_score,
    AVG(los_days) AS avg_los,
    AVG(mortality) AS avg_mortality,
    AVG(CASE WHEN instability_score >= 3 THEN 1.0 ELSE 0.0 END) AS critical_rate,
    COUNT(*) AS n_admissions
  FROM instability_scores
  GROUP BY hf_flag
)
SELECT 
  CASE WHEN hf_flag = 1 THEN 'Heart Failure Males 37-47' ELSE 'General Males 37-47' END AS cohort_type,
  ROUND(AVG(max_instability_score), 2) AS avg_max_instability_score,
  ROUND(AVG(critical_rate) * 100, 2) AS critical_event_rate_percent,
  ROUND(AVG(avg_los), 2) AS avg_los_days,
  ROUND(AVG(avg_mortality) * 100, 2) AS mortality_rate_percent,
  SUM(n_admissions) AS n_admissions
FROM max_scores
GROUP BY hf_flag, cohort_type
ORDER BY hf_flag DESC;