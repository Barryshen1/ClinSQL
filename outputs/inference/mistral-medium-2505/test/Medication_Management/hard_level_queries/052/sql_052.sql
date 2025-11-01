WITH
-- Define HHS ICD codes
hhs_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('E1100', 'E1101', 'E1165')  -- Example HHS ICD codes
),

-- Identify female patients aged 68-78 with HHS
hhs_patients AS (
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
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN hhs_icd_codes h ON d.icd_code = h.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Identify all female inpatients aged 68-78 (control group)
control_patients AS (
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
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Calculate medication complexity within 72 hours of admission
medication_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_medications,
    COUNT(DISTINCT p.route) AS unique_routes,
    COUNT(DISTINCT p.doses_per_24_hrs) AS unique_frequencies
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN hhs_patients h ON p.hadm_id = h.hadm_id
  WHERE p.starttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY p.subject_id, p.hadm_id
),

-- Identify hyperkalemia-risk drugs (example list)
hyperkalemia_risk_drugs AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN (
    'ACE Inhibitor', 'ARB', 'Potassium-sparing diuretic', 'NSAID'
  )
),

-- Calculate hyperkalemia-risk drug interactions
hyperkalemia_interactions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS hyperkalemia_risk_drugs_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN hyperkalemia_risk_drugs h ON p.drug = h.itemid
  JOIN hhs_patients hp ON p.hadm_id = hp.hadm_id
  GROUP BY p.subject_id, p.hadm_id
),

-- Calculate LOS and mortality
los_mortality AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS los_hours,
    hospital_expire_flag
  FROM hhs_patients
)

-- Final results
SELECT
  'HHS Patients' AS cohort,
  COUNT(DISTINCT h.subject_id) AS patient_count,
  AVG(m.unique_medications) AS avg_medication_complexity,
  PERCENTILE_CONT(hi.hyperkalemia_risk_drugs_count, 0.5) OVER() AS median_hyperkalemia_risk_rank,
  COUNT(DISTINCT CASE WHEN hi.hyperkalemia_risk_drugs_count > 0 THEN h.subject_id END) /
    COUNT(DISTINCT h.subject_id) AS percent_with_hyperkalemia_risk,
  PERCENTILE_CONT(lm.los_hours, 0.75) OVER() AS top_quartile_los,
  AVG(CASE WHEN lm.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM hhs_patients h
LEFT JOIN medication_complexity m ON h.subject_id = m.subject_id AND h.hadm_id = m.hadm_id
LEFT JOIN hyperkalemia_interactions hi ON h.subject_id = hi.subject_id AND h.hadm_id = hi.hadm_id
LEFT JOIN los_mortality lm ON h.subject_id = lm.subject_id AND h.hadm_id = lm.hadm_id

UNION ALL

SELECT
  'All Female Patients 68-78' AS cohort,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  AVG(mc.unique_medications) AS avg_medication_complexity,
  PERCENTILE_CONT(hic.hyperkalemia_risk_drugs_count, 0.5) OVER() AS median_hyperkalemia_risk_rank,
  COUNT(DISTINCT CASE WHEN hic.hyperkalemia_risk_drugs_count > 0 THEN c.subject_id END) /
    COUNT(DISTINCT c.subject_id) AS percent_with_hyperkalemia_risk,
  PERCENTILE_CONT(lmc.los_hours, 0.75) OVER() AS top_quartile_los,
  AVG(CASE WHEN lmc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM control_patients c
LEFT JOIN (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_medications,
    COUNT(DISTINCT p.route) AS unique_routes,
    COUNT(DISTINCT p.doses_per_24_hrs) AS unique_frequencies
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN control_patients c ON p.hadm_id = c.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY p.subject_id, p.hadm_id
) mc ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
LEFT JOIN (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS hyperkalemia_risk_drugs_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN hyperkalemia_risk_drugs h ON p.drug = h.itemid
  JOIN control_patients c ON p.hadm_id = c.hadm_id
  GROUP BY p.subject_id, p.hadm_id
) hic ON c.subject_id = hic.subject_id AND c.hadm_id = hic.hadm_id
LEFT JOIN (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS los_hours,
    hospital_expire_flag
  FROM control_patients
) lmc ON c.subject_id = lmc.subject_id AND c.hadm_id = lmc.hadm_id;