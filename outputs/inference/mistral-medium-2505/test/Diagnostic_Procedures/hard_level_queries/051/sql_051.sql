WITH
-- Get male patients aged 90-100
elderly_male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age AS current_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND (EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age) BETWEEN 90 AND 100
),

-- Get their ICU stays with sepsis
sepsis_icu_stays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    d.icd_code,
    d.long_title AS sepsis_diagnosis,
    a.hospital_expire_flag
  FROM
    elderly_male_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    -- Sepsis ICD-10 codes (simplified - would need full list in production)
    d.icd_code IN (
      'A419', 'A4151', 'A4152', 'A4159', 'A4101', 'A4102', 'A4109',
      'A411', 'A412', 'A413', 'A414', 'A418', 'A419', 'R6520', 'R6521'
    )
    -- Only first ICU stay per admission
    AND i.stay_id = (
      SELECT MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE subject_id = i.subject_id AND hadm_id = i.hadm_id
    )
),

-- Count diagnostics in first 24 hours
diagnostic_counts AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    -- Count distinct lab tests
    COUNT(DISTINCT l.itemid) AS lab_test_count,
    -- Count distinct microbiology tests
    COUNT(DISTINCT m.test_itemid) AS micro_test_count,
    -- Count distinct imaging procedures (HCPCS codes for imaging)
    COUNT(DISTINCT CASE WHEN h.short_description LIKE '%imaging%' THEN h.hcpcs_cd END) AS imaging_count
  FROM
    sepsis_icu_stays s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON s.subject_id = l.subject_id AND s.hadm_id = l.hadm_id
    AND l.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 24 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
    AND m.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 24 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id
    AND h.chartdate = DATE(s.icu_intime)
    AND h.short_description LIKE '%imaging%'
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id
),

-- Calculate total diagnostic utilization
diagnostic_utilization AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    lab_test_count + micro_test_count + imaging_count AS total_diagnostics
  FROM
    diagnostic_counts
),

-- Calculate overall ICU admissions for comparison
overall_icu_admissions AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    AVG(los) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),

-- Calculate percentiles for diagnostic utilization
diagnostic_stats AS (
  SELECT
    STDDEV(total_diagnostics) AS sd_diagnostic_utilization,
    PERCENTILE_CONT(total_diagnostics, 0.75) OVER() AS p75_diagnostic_utilization,
    PERCENTILE_CONT(total_diagnostics, 0.95) OVER() AS p95_diagnostic_utilization
  FROM
    diagnostic_utilization
  LIMIT 1
)

-- Final results
SELECT
  -- Diagnostic utilization metrics
  ds.sd_diagnostic_utilization,
  ds.p75_diagnostic_utilization,
  ds.p95_diagnostic_utilization,

  -- Mortality and LOS for sepsis patients
  SUM(CASE WHEN s.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT s.subject_id) * 100 AS sepsis_mortality_rate,
  AVG(s.icu_los) AS avg_sepsis_los,

  -- Comparison with overall ICU
  COUNT(DISTINCT s.subject_id) AS sepsis_admissions,
  o.total_admissions AS overall_icu_admissions,
  COUNT(DISTINCT s.subject_id) / o.total_admissions * 100 AS sepsis_percentage_of_icu,

  -- Overall ICU metrics
  o.avg_los AS overall_icu_avg_los,
  o.mortality_rate AS overall_icu_mortality_rate
FROM
  diagnostic_utilization d
JOIN
  sepsis_icu_stays s ON d.subject_id = s.subject_id AND d.hadm_id = s.hadm_id AND d.stay_id = s.stay_id
CROSS JOIN
  overall_icu_admissions o
CROSS JOIN
  diagnostic_stats ds;