WITH
-- Define DKA ICD codes (example codes, adjust as needed)
dka_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('E13.10', 'E13.11', 'E10.10', 'E10.11', 'E11.10', 'E11.11')
),

-- Define hyperkalemia-risk drugs (example itemids, adjust as needed)
hyperkalemia_risk_drugs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN (
    'ACE Inhibitor', 'ARB', 'Potassium-Sparing Diuretic', 'NSAID', 'Spironolactone', 'Eplerenone'
  )
),

-- Get female patients aged 84-94 with DKA
eligible_patients AS (
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
  JOIN dka_icd_codes dka ON d.icd_code = dka.icd_code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- Get medication complexity for each patient within first 48h
medication_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_med_count,
    SUM(p.doses_per_24_hrs) AS total_daily_doses,
    COUNT(*) AS total_med_orders
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_patients ep ON p.subject_id = ep.subject_id AND p.hadm_id = ep.hadm_id
  WHERE p.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
  GROUP BY p.subject_id, p.hadm_id
),

-- Identify patients with hyperkalemia-risk drugs in first 48h
hyperkalemia_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN hyperkalemia_risk_drugs h ON p.drug LIKE CONCAT('%', h.label, '%')  -- More flexible matching
  JOIN eligible_patients ep ON p.subject_id = ep.subject_id AND p.hadm_id = ep.hadm_id
  WHERE p.starttime BETWEEN ep.admittime AND TIMESTAMP_ADD(ep.admittime, INTERVAL 48 HOUR)
),

-- Calculate complexity percentiles for eligible patients
complexity_percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    unique_med_count,
    total_daily_doses,
    total_med_orders,
    PERCENT_RANK() OVER (ORDER BY unique_med_count) AS complexity_percentile
  FROM medication_complexity
)

-- Final comparison
SELECT
  'With hyperkalemia-risk drugs' AS group_name,
  AVG(mc.unique_med_count) AS mean_medication_complexity,
  AVG(mc.total_daily_doses) AS mean_daily_doses,
  AVG(mc.total_med_orders) AS mean_med_orders,
  AVG(ep.los_hours) AS mean_los_hours,
  AVG(CASE WHEN ep.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  APPROX_QUANTILES(mc.unique_med_count, 4)[OFFSET(3)] AS top_quartile_complexity,
  AVG(CASE WHEN mc.complexity_percentile >= 0.75 THEN ep.los_hours ELSE NULL END) AS top_quartile_los,
  AVG(CASE WHEN mc.complexity_percentile >= 0.75 AND ep.hospital_expire_flag = 1 THEN 1 ELSE NULL END) AS top_quartile_mortality
FROM eligible_patients ep
JOIN medication_complexity mc ON ep.subject_id = mc.subject_id AND ep.hadm_id = mc.hadm_id
JOIN complexity_percentiles cp ON mc.subject_id = cp.subject_id AND mc.hadm_id = cp.hadm_id
WHERE (ep.subject_id, ep.hadm_id) IN (SELECT subject_id, hadm_id FROM hyperkalemia_patients)

UNION ALL

SELECT
  'Without hyperkalemia-risk drugs' AS group_name,
  AVG(mc.unique_med_count) AS mean_medication_complexity,
  AVG(mc.total_daily_doses) AS mean_daily_doses,
  AVG(mc.total_med_orders) AS mean_med_orders,
  AVG(ep.los_hours) AS mean_los_hours,
  AVG(CASE WHEN ep.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  APPROX_QUANTILES(mc.unique_med_count, 4)[OFFSET(3)] AS top_quartile_complexity,
  AVG(CASE WHEN mc.complexity_percentile >= 0.75 THEN ep.los_hours ELSE NULL END) AS top_quartile_los,
  AVG(CASE WHEN mc.complexity_percentile >= 0.75 AND ep.hospital_expire_flag = 1 THEN 1 ELSE NULL END) AS top_quartile_mortality
FROM eligible_patients ep
JOIN medication_complexity mc ON ep.subject_id = mc.subject_id AND ep.hadm_id = mc.hadm_id
JOIN complexity_percentiles cp ON mc.subject_id = cp.subject_id AND mc.hadm_id = cp.hadm_id
WHERE (ep.subject_id, ep.hadm_id) NOT IN (SELECT subject_id, hadm_id FROM hyperkalemia_patients);