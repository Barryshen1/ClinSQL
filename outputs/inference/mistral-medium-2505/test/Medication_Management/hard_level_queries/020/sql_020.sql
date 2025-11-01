WITH
-- Define high-risk drugs (example list - should be expanded based on clinical guidelines)
high_risk_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    'WARFARIN', 'HEPARIN', 'INSULIN', 'DIGOXIN', 'AMIODARONE',
    'PHENYTOIN', 'THEOPHYLLINE', 'LITHIUM', 'METHOTREXATE', 'CARBAMAZEPINE'
  )
),

-- Get female patients aged 78-88
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
),

-- Get all medications within first 7 days of admission
medications_7days AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    e.admittime,
    p.drug,
    p.route,
    CASE WHEN h.drug IS NOT NULL THEN 1 ELSE 0 END AS is_high_risk
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_patients e ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
  LEFT JOIN high_risk_drugs h ON p.drug = h.drug
  WHERE p.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 7 DAY)

  UNION ALL

  SELECT
    ph.subject_id,
    ph.hadm_id,
    e.admittime,
    ph.medication AS drug,
    ph.route,
    CASE WHEN h.drug IS NOT NULL THEN 1 ELSE 0 END AS is_high_risk
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN eligible_patients e ON ph.subject_id = e.subject_id AND ph.hadm_id = e.hadm_id
  LEFT JOIN high_risk_drugs h ON ph.medication = h.drug
  WHERE ph.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 7 DAY)
),

-- Calculate medication complexity score for each patient
medication_scores AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_drugs,
    SUM(is_high_risk) AS high_risk_drugs,
    COUNT(DISTINCT route) AS unique_routes,
    COUNT(DISTINCT drug) + 2 * SUM(is_high_risk) + COUNT(DISTINCT route) AS complexity_score
  FROM medications_7days
  GROUP BY subject_id, hadm_id
),

-- Calculate tertiles
tertiles AS (
  SELECT
    complexity_score,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM medication_scores
),

-- Get readmission information
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON
    a1.subject_id = a2.subject_id AND
    a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  WHERE a1.subject_id IN (SELECT subject_id FROM eligible_patients)
)

-- Final result
SELECT
  t.tertile,
  COUNT(DISTINCT m.subject_id) AS patient_count,
  MIN(m.complexity_score) AS min_score,
  MAX(m.complexity_score) AS max_score,
  ROUND(AVG(e.los_days), 1) AS avg_los_days,
  ROUND(100 * SUM(CASE WHEN e.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT m.subject_id), 1) AS mortality_pct,
  ROUND(100 * SUM(r.readmitted_30d) / COUNT(DISTINCT m.subject_id), 1) AS readmission_30d_pct
FROM medication_scores m
JOIN tertiles t ON m.complexity_score = t.complexity_score
JOIN eligible_patients e ON m.subject_id = e.subject_id AND m.hadm_id = e.hadm_id
JOIN readmissions r ON m.subject_id = r.subject_id AND m.hadm_id = r.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;