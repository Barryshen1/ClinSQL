WITH
-- Define hepatic failure ICD codes
hepatic_failure_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('K720', 'K721', 'K729', 'K717', 'K700', 'K701', 'K702', 'K703', 'K704', 'K709')
),

-- Get qualifying patients with hepatic failure
qualifying_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN hepatic_failure_codes h ON d.icd_code = h.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

-- Get first qualifying admission for each patient
first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) as admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN qualifying_patients q ON a.subject_id = q.subject_id
),

-- Get medications in first 72 hours
first_72h_medications AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_med_count,
    COUNT(*) AS total_med_admin,
    SUM(CASE WHEN p.route IN ('IV', 'IVPB', 'IVPUSH') THEN 1 ELSE 0 END) AS iv_med_count,
    SUM(CASE WHEN p.drug IN ('HEPARIN', 'INSULIN', 'WARFARIN') THEN 1 ELSE 0 END) AS high_risk_med_count
  FROM first_admissions f
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON f.hadm_id = p.hadm_id
  WHERE f.admission_rank = 1
    AND p.starttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id, f.hadm_id
),

-- Calculate medication complexity score
medication_scores AS (
  SELECT
    subject_id,
    hadm_id,
    unique_med_count * 2 +
    total_med_admin * 0.5 +
    iv_med_count * 3 +
    high_risk_med_count * 5 AS complexity_score
  FROM first_72h_medications
),

-- Calculate quintiles
score_quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM medication_scores
),

-- Get length of stay
los_data AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.quintile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS length_of_stay_days
  FROM score_quintiles s
  JOIN first_admissions a ON s.hadm_id = a.hadm_id
  WHERE a.admission_rank = 1
),

-- Get 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    MAX(CASE WHEN a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS had_30day_readmission
  FROM first_admissions a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.admittime
    AND a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  WHERE a1.admission_rank = 1
  GROUP BY a1.subject_id, a1.hadm_id
)

-- Final results by quintile
SELECT
  q.quintile,
  COUNT(DISTINCT q.subject_id) AS n,
  MIN(m.complexity_score) AS min_score,
  MAX(m.complexity_score) AS max_score,
  ROUND(AVG(m.complexity_score), 2) AS mean_score,
  ROUND(AVG(l.length_of_stay_days), 2) AS mean_los_days,
  ROUND(100 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.subject_id), 2) AS inhospital_mortality_pct,
  ROUND(100 * SUM(r.had_30day_readmission) / COUNT(DISTINCT q.subject_id), 2) AS day30_readmission_pct
FROM score_quintiles q
JOIN medication_scores m ON q.subject_id = m.subject_id AND q.hadm_id = m.hadm_id
JOIN los_data l ON q.subject_id = l.subject_id AND q.hadm_id = l.hadm_id
JOIN first_admissions a ON q.hadm_id = a.hadm_id AND a.admission_rank = 1
LEFT JOIN readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;