WITH
-- Define CYP3A4 interacting drugs (this would need to be expanded with actual drug codes)
cyp3a4_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    -- Example drugs - this list should be expanded with actual CYP3A4 interacting drugs
    'WARFARIN', 'DIGOXIN', 'PHENYTOIN', 'THEOPHYLLINE', 'CARBAMAZEPINE'
  )
),

-- Define NTI drugs (this would need to be expanded with actual drug codes)
nti_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    -- Example NTI drugs - this list should be expanded with actual NTI drugs
    'WARFARIN', 'DIGOXIN', 'PHENYTOIN', 'THEOPHYLLINE', 'CARBAMAZEPINE',
    'LITHIUM', 'AMIODARONE', 'CYCLOSPORINE', 'TACROLIMUS'
  )
),

-- Get patients with CYP3A4 interactions affecting NTI drugs
patients_with_interactions AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
  JOIN cyp3a4_drugs c ON pr.drug = c.drug
  JOIN nti_drugs n ON pr.drug = n.drug
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- Get all female patients aged 48-58
age_matched_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- Get stroke patients (ICD-10 codes I63.x)
stroke_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code LIKE 'I63%'
),

-- Calculate Elixhauser comorbidity score (simplified version)
comorbidity_scores AS (
  SELECT
    d.subject_id,
    SUM(CASE
      WHEN d.icd_code IN (
        -- Example ICD codes for comorbidities - this should be expanded
        'E11.65', 'I10', 'I50.9', 'J44.9', 'F33.9', 'K21.9', 'K25.9', 'K27.9', 'K29.9',
        'N18.9', 'N19', 'N39.0', 'E11.9', 'E13.9', 'E10.9', 'E14.9', 'E08.9', 'E09.9', 'E11.22'
      ) THEN 1
      ELSE 0
    END) AS comorbidity_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id
),

-- Calculate LOS and mortality for each group
patient_metrics AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    cs.comorbidity_score,
    CASE WHEN p.subject_id IN (SELECT subject_id FROM patients_with_interactions) THEN 'With CYP3A4 interactions'
         ELSE 'Without CYP3A4 interactions' END AS interaction_group,
    CASE WHEN p.subject_id IN (SELECT subject_id FROM stroke_patients) THEN 1 ELSE 0 END AS is_stroke_patient
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN comorbidity_scores cs ON p.subject_id = cs.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- Calculate percentiles for complexity score
percentiles AS (
  SELECT
    interaction_group,
    PERCENTILE_CONT(comorbidity_score, 0.25) OVER (PARTITION BY interaction_group) AS q1,
    PERCENTILE_CONT(comorbidity_score, 0.5) OVER (PARTITION BY interaction_group) AS median,
    PERCENTILE_CONT(comorbidity_score, 0.75) OVER (PARTITION BY interaction_group) AS q3,
    comorbidity_score
  FROM patient_metrics
),

-- Get top quartile stroke patients
top_quartile_stroke AS (
  SELECT
    p.subject_id,
    p.los_days,
    p.hospital_expire_flag,
    p.comorbidity_score,
    p.interaction_group
  FROM patient_metrics p
  JOIN (SELECT interaction_group, q3 FROM percentiles GROUP BY interaction_group, q3) per
    ON p.interaction_group = per.interaction_group
  WHERE p.is_stroke_patient = 1
    AND p.comorbidity_score >= per.q3
)

-- Final results
SELECT
  'Comparison by CYP3A4 interaction status' AS analysis_type,
  interaction_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(comorbidity_score) AS avg_complexity_score,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) / COUNT(DISTINCT subject_id) AS mortality_rate
FROM patient_metrics
GROUP BY interaction_group

UNION ALL

SELECT
  'Top quartile stroke patients' AS analysis_type,
  interaction_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(comorbidity_score) AS avg_complexity_score,
  AVG(los_days) AS avg_los_days,
  SUM(hospital_expire_flag) / COUNT(DISTINCT subject_id) AS mortality_rate
FROM top_quartile_stroke
GROUP BY interaction_group
ORDER BY analysis_type, interaction_group;