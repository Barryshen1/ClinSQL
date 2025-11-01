WITH
-- Define multi-trauma ICD codes (example codes - adjust as needed)
trauma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%trauma%'
     OR LOWER(long_title) LIKE '%fracture%'
     OR LOWER(long_title) LIKE '%injury%'
),

-- Get female patients aged 68-78 with multi-trauma
female_trauma_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN trauma_codes t ON d.icd_code = t.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
),

-- Calculate medication complexity in first 24 hours
med_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_meds,
    COUNT(*) AS total_med_orders,
    COUNT(DISTINCT p.route) AS unique_routes,
    SUM(CASE WHEN ph.frequency LIKE '%QID%' OR ph.frequency LIKE '%4 times%' THEN 1 ELSE 0 END) AS high_freq_meds
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON p.subject_id = ph.subject_id AND p.hadm_id = ph.hadm_id AND p.pharmacy_id = ph.pharmacy_id
  JOIN female_trauma_patients f ON p.subject_id = f.subject_id AND p.hadm_id = f.hadm_id
  WHERE p.starttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 24 HOUR)
  GROUP BY p.subject_id, p.hadm_id
),

-- Identify serotonergic medications (example list - expand as needed)
serotonergic_meds AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%fluoxetine%'
     OR LOWER(drug) LIKE '%sertraline%'
     OR LOWER(drug) LIKE '%paroxetine%'
     OR LOWER(drug) LIKE '%citalopram%'
     OR LOWER(drug) LIKE '%escitalopram%'
     OR LOWER(drug) LIKE '%venlafaxine%'
     OR LOWER(drug) LIKE '%duloxetine%'
     OR LOWER(drug) LIKE '%amitriptyline%'
),

-- Flag patients with serotonergic interaction risk (≥2 serotonergic meds)
serotonergic_risk AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    COUNT(DISTINCT p.drug) AS serotonergic_count
  FROM med_complexity m
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON m.subject_id = p.subject_id AND m.hadm_id = p.hadm_id
  JOIN serotonergic_meds s ON p.drug = s.drug
  JOIN female_trauma_patients f ON m.subject_id = f.subject_id AND m.hadm_id = f.hadm_id
  WHERE p.starttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 24 HOUR)
  GROUP BY m.subject_id, m.hadm_id
  HAVING COUNT(DISTINCT p.drug) >= 2
),

-- Calculate complexity quartiles
complexity_quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    unique_meds,
    total_med_orders,
    unique_routes,
    high_freq_meds,
    NTILE(4) OVER (ORDER BY unique_meds + total_med_orders + unique_routes + high_freq_meds) AS complexity_quartile,
    PERCENT_RANK() OVER (ORDER BY unique_meds + total_med_orders + unique_routes + high_freq_meds) AS complexity_percentile
  FROM med_complexity
),

-- Final analysis
final_results AS (
  SELECT
    c.complexity_quartile,
    CASE WHEN s.subject_id IS NOT NULL THEN 'Serotonergic Risk' ELSE 'Other Multi-Trauma' END AS patient_group,
    AVG(c.complexity_percentile) AS avg_complexity_percentile,
    AVG(TIMESTAMP_DIFF(f.dischtime, f.admittime, HOUR)/24) AS avg_los_days,
    SUM(CASE WHEN f.hospital_expire_flag = 1 OR f.dod IS NOT NULL THEN 1 ELSE 0 END) AS mortality_count,
    COUNT(*) AS patient_count
  FROM complexity_quartiles c
  LEFT JOIN serotonergic_risk s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id
  JOIN female_trauma_patients f ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  GROUP BY c.complexity_quartile, patient_group
)

-- Main results
SELECT
  complexity_quartile,
  patient_group,
  avg_complexity_percentile,
  avg_los_days,
  mortality_count,
  patient_count,
  mortality_count/patient_count AS mortality_rate
FROM final_results
ORDER BY complexity_quartile, patient_group;

-- Additional analysis for top quartile
SELECT
  'Top Quartile' AS complexity_group,
  AVG(TIMESTAMP_DIFF(f.dischtime, f.admittime, HOUR)/24) AS avg_los_days,
  SUM(CASE WHEN f.hospital_expire_flag = 1 OR f.dod IS NOT NULL THEN 1 ELSE 0 END) AS mortality_count,
  COUNT(*) AS patient_count,
  SUM(CASE WHEN f.hospital_expire_flag = 1 OR f.dod IS NOT NULL THEN 1 ELSE 0 END)/COUNT(*) AS mortality_rate
FROM complexity_quartiles c
JOIN female_trauma_patients f ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
WHERE c.complexity_quartile = 4;