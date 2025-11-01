WITH
-- Define high-risk drug classes (example - adjust based on clinical needs)
high_risk_drugs AS (
  SELECT DISTINCT drug_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug_type IN ('Opioid', 'Anticoagulant', 'Insulin', 'Chemotherapy')
),

-- Get surgical admissions for female patients aged 51-61
surgical_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type = 'SURGERY'
),

-- Calculate medication complexity per admission
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    -- Count unique drugs
    COUNT(DISTINCT drug) AS unique_drug_count,
    -- Count high-risk drug classes (weighted x2)
    SUM(CASE WHEN drug_type IN (SELECT drug_type FROM high_risk_drugs) THEN 2 ELSE 1 END) AS weighted_drug_count,
    -- Total complexity score
    COUNT(DISTINCT drug) + SUM(CASE WHEN drug_type IN (SELECT drug_type FROM high_risk_drugs) THEN 2 ELSE 1 END) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM surgical_patients)
  GROUP BY subject_id, hadm_id
),

-- Calculate quartiles of complexity scores
complexity_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM med_complexity
),

-- Calculate 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  WHERE a1.hadm_id IN (SELECT hadm_id FROM surgical_patients)
)

-- Final results by quartile
SELECT
  q.quartile,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id) AS mortality_percentage,
  SUM(CASE WHEN r.readmission_hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id) AS readmission_percentage
FROM complexity_quartiles q
JOIN surgical_patients a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
LEFT JOIN readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.original_hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;