WITH
-- Get male patients aged 79-89 with pulmonary embolism
pe_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND d.icd_code LIKE 'I26%'  -- Pulmonary embolism ICD-10 codes
    AND d.icd_version = 10
),

-- Get diagnostic tests in first 24 hours of ICU admission
diagnostic_tests AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    COUNT(DISTINCT l.itemid) AS num_lab_tests,
    0 AS num_micro_tests
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    pe_patients p
    ON l.subject_id = p.subject_id AND l.hadm_id = p.hadm_id
  WHERE
    l.charttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 24 HOUR)
  GROUP BY
    l.subject_id, l.hadm_id

  UNION ALL

  SELECT
    m.subject_id,
    m.hadm_id,
    0 AS num_lab_tests,
    COUNT(DISTINCT m.test_itemid) AS num_micro_tests
  FROM
    `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
  JOIN
    pe_patients p
    ON m.subject_id = p.subject_id AND m.hadm_id = p.hadm_id
  WHERE
    m.charttime BETWEEN p.icu_intime AND TIMESTAMP_ADD(p.icu_intime, INTERVAL 24 HOUR)
  GROUP BY
    m.subject_id, m.hadm_id
),

-- Aggregate diagnostic tests per patient
pe_diagnostic_scores AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.icu_los,
    p.hospital_expire_flag,
    SUM(COALESCE(dt.num_lab_tests, 0) + COALESCE(dt.num_micro_tests, 0)) AS diagnostic_utilization_score
  FROM
    pe_patients p
  LEFT JOIN
    diagnostic_tests dt
    ON p.subject_id = dt.subject_id AND p.hadm_id = dt.hadm_id
  GROUP BY
    p.subject_id, p.hadm_id, p.stay_id, p.icu_los, p.hospital_expire_flag
),

-- Get general ICU population for comparison
general_icu_population AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
)

-- Final results
SELECT
  'PE Patients' AS cohort,
  PERCENTILE_CONT(diagnostic_utilization_score, 0.75) OVER() AS percentile_75_diagnostic_score,
  AVG(icu_los) AS avg_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM
  pe_diagnostic_scores

UNION ALL

SELECT
  'General ICU Population' AS cohort,
  NULL AS percentile_75_diagnostic_score,
  AVG(icu_los) AS avg_icu_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM
  general_icu_population;