WITH
-- Define sepsis ICD codes (example codes, adjust as needed)
sepsis_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
     OR LOWER(long_title) LIKE '%septicemia%'
),

-- Define QT-prolonging and bleeding-risk drugs (example lists, adjust as needed)
qt_drugs AS (
  SELECT 'amiodarone' AS drug_name UNION ALL
  SELECT 'quinidine' UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'clarithromycin'
),

bleeding_risk_drugs AS (
  SELECT 'warfarin' AS drug_name UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'clopidogrel' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'rivaroxaban'
),

-- Get male patients aged 80-90 with sepsis
sepsis_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN sepsis_icd_codes s ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

-- Get medications in first 24 hours
first_24h_meds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.route,
    p.doses_per_24_hrs,
    p.form_val_disp,
    p.form_unit_disp,
    CASE WHEN LOWER(p.drug) IN (SELECT LOWER(drug_name) FROM qt_drugs) THEN 1 ELSE 0 END AS is_qt_drug,
    CASE WHEN LOWER(p.drug) IN (SELECT LOWER(drug_name) FROM bleeding_risk_drugs) THEN 1 ELSE 0 END AS is_bleeding_risk_drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN sepsis_patients sp ON p.subject_id = sp.subject_id AND p.hadm_id = sp.hadm_id
  WHERE p.starttime IS NOT NULL
    AND TIMESTAMP_DIFF(p.starttime, sp.admittime, HOUR) <= 24
),

-- Calculate medication complexity score (example: count of unique meds + routes + frequency)
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_med_count,
    COUNT(DISTINCT route) AS unique_route_count,
    SUM(doses_per_24_hrs) AS total_daily_doses,
    COUNT(DISTINCT drug) + COUNT(DISTINCT route) + SUM(doses_per_24_hrs) AS complexity_score,
    MAX(is_qt_drug) AS has_qt_drug,
    MAX(is_bleeding_risk_drug) AS has_bleeding_risk_drug
  FROM first_24h_meds
  GROUP BY subject_id, hadm_id
),

-- Group patients by medication risk profile
patient_groups AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.complexity_score,
    sp.los_hours,
    sp.hospital_expire_flag,
    CASE
      WHEN mc.has_qt_drug = 1 AND mc.has_bleeding_risk_drug = 1 THEN 'Both QT and Bleeding Risk'
      ELSE 'Other'
    END AS risk_group
  FROM med_complexity mc
  JOIN sepsis_patients sp ON mc.subject_id = sp.subject_id AND mc.hadm_id = sp.hadm_id
),

-- Calculate percentiles and quartiles
percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    risk_group,
    complexity_score,
    PERCENT_RANK() OVER (PARTITION BY risk_group ORDER BY complexity_score) AS percentile_rank,
    NTILE(4) OVER (PARTITION BY risk_group ORDER BY complexity_score) AS quartile
  FROM patient_groups
)

-- Final analysis
SELECT
  pg.risk_group,
  COUNT(*) AS patient_count,
  AVG(pg.complexity_score) AS avg_complexity_score,
  AVG(pg.los_hours) AS avg_los_hours,
  SUM(CASE WHEN pg.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  AVG(CASE WHEN p.quartile = 4 THEN pg.los_hours ELSE NULL END) AS top_quartile_avg_los,
  AVG(CASE WHEN p.quartile = 4 THEN pg.hospital_expire_flag ELSE NULL END) AS top_quartile_mortality_rate
FROM patient_groups pg
JOIN percentiles p ON pg.subject_id = p.subject_id AND pg.hadm_id = p.hadm_id
GROUP BY pg.risk_group
ORDER BY pg.risk_group;