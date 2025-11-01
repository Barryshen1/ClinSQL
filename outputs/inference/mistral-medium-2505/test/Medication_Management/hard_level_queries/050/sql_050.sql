WITH
-- Define AKI patients (female, age 81-91)
aki_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.icd_code LIKE 'N17%'  -- AKI ICD-10 codes
    AND d.icd_version = 10
),

-- Define CNS-depressant drugs
cns_depressants AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'lorazepam', 'diazepam', 'midazolam', 'morphine', 'fentanyl',
    'hydromorphone', 'oxycodone', 'alprazolam', 'clonazepam', 'zolpidem'
  )
),

-- Define nephrotoxic drugs (specific examples)
nephrotoxic_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'vancomycin', 'gentamicin', 'tobramycin', 'amphotericin b', 'cisplatin',
    'ibuprofen', 'naproxen', 'lisinopril', 'losartan', 'furosemide'
  )
),

-- Identify patients with both drug types
patients_with_both_drugs AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    aki_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  JOIN
    cns_depressants c ON LOWER(pr.drug) = LOWER(c.drug)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr2 ON p.subject_id = pr2.subject_id AND p.hadm_id = pr2.hadm_id
  JOIN
    nephrotoxic_drugs n ON LOWER(pr2.drug) = LOWER(n.drug)
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Calculate medication complexity score
medication_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_med_count,
    COUNT(DISTINCT pr.route) AS unique_route_count,
    SUM(CASE WHEN pr.doses_per_24_hrs IS NOT NULL THEN 1 ELSE 0 END) AS frequency_count,
    -- Simple complexity score (adjust weights as needed)
    COUNT(DISTINCT pr.drug) * 0.3 +
    COUNT(DISTINCT pr.route) * 0.2 +
    SUM(CASE WHEN pr.doses_per_24_hrs IS NOT NULL THEN 1 ELSE 0 END) * 0.5 AS complexity_score
  FROM
    aki_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Pre-calculate LOS quartiles
los_quartiles AS (
  SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS top_quartile_threshold
  FROM
    aki_patients
),

-- Combine all data
final_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    a.hospital_expire_flag,
    m.complexity_score,
    CASE WHEN p.subject_id IS NOT NULL THEN 'Both Drugs' ELSE 'Other AKI' END AS patient_group,
    q.top_quartile_threshold
  FROM
    aki_patients a
  JOIN
    medication_complexity m ON a.subject_id = m.subject_id AND a.hadm_id = m.hadm_id
  LEFT JOIN
    patients_with_both_drugs p ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  CROSS JOIN
    los_quartiles q
)

-- Final analysis
SELECT
  patient_group,
  COUNT(*) AS patient_count,
  -- Complexity score statistics
  APPROX_QUANTILES(complexity_score, 4) AS complexity_quartiles,
  AVG(complexity_score) AS mean_complexity,
  -- LOS statistics
  APPROX_QUANTILES(los_days, 4) AS los_quartiles,
  AVG(los_days) AS mean_los,
  -- Mortality statistics
  SUM(hospital_expire_flag) AS total_deaths,
  AVG(hospital_expire_flag) AS mortality_rate,
  -- Top quartile LOS and mortality
  SUM(CASE WHEN los_days > top_quartile_threshold THEN 1 ELSE 0 END) AS top_quartile_los_count,
  SUM(CASE WHEN los_days > top_quartile_threshold AND hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS top_quartile_los_deaths
FROM
  final_data
GROUP BY
  patient_group, top_quartile_threshold
ORDER BY
  patient_group;