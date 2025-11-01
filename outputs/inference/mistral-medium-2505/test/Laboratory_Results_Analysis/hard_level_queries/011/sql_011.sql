WITH
-- Define age range and gender with proper join to get hadm_id
age_gender_filter AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
),

-- Identify AKI patients (ICD-10 codes N17.x)
aki_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    age_gender_filter a ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  WHERE
    d.icd_code LIKE 'N17%'  -- AKI ICD-10 codes
),

-- Identify control patients (same age/gender but no AKI)
control_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    age_gender_filter a
  LEFT JOIN
    aki_patients k ON a.subject_id = k.subject_id AND a.hadm_id = k.hadm_id
  WHERE
    k.subject_id IS NULL  -- No AKI diagnosis
),

-- Calculate 72-hour lab instability score
lab_instability AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    -- Count of abnormal lab values (outside reference range)
    COUNT(CASE WHEN (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper) THEN 1 END) AS abnormal_lab_count,
    -- Total lab tests for normalization
    COUNT(*) AS total_lab_tests
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN
    age_gender_filter a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    -- Within 72 hours of admission
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    -- Focus on key labs for instability score
    AND d.category IN ('Chemistry', 'Hematology', 'Blood Gas')
  GROUP BY
    l.subject_id, l.hadm_id
),

-- Calculate critical event frequency
critical_events AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Count distinct ICU stays
    COUNT(DISTINCT i.stay_id) AS icu_stays,
    -- Count distinct procedures
    COUNT(DISTINCT p.hadm_id) AS procedure_count,
    -- Count distinct medications
    COUNT(DISTINCT pr.hadm_id) AS medication_count
  FROM
    age_gender_filter a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  GROUP BY
    a.subject_id, a.hadm_id
),

-- Calculate length of stay and mortality (now using data from age_gender_filter)
los_mortality AS (
  SELECT
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24 AS length_of_stay_days,
    hospital_expire_flag AS in_hospital_mortality
  FROM
    age_gender_filter
)

-- Final comparison between AKI and control groups
SELECT
  'AKI Patients' AS group_type,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  AVG(CASE WHEN li.abnormal_lab_count > 0 THEN li.abnormal_lab_count * 1.0 / li.total_lab_tests ELSE 0 END) AS mean_lab_instability_score,
  AVG(ce.icu_stays) AS avg_icu_stays,
  AVG(ce.procedure_count) AS avg_procedure_count,
  AVG(ce.medication_count) AS avg_medication_count,
  AVG(lm.length_of_stay_days) AS avg_length_of_stay,
  SUM(lm.in_hospital_mortality) * 1.0 / COUNT(DISTINCT a.subject_id) AS mortality_rate
FROM
  aki_patients a
LEFT JOIN
  lab_instability li ON a.subject_id = li.subject_id AND a.hadm_id = li.hadm_id
LEFT JOIN
  critical_events ce ON a.subject_id = ce.subject_id AND a.hadm_id = ce.hadm_id
LEFT JOIN
  los_mortality lm ON a.subject_id = lm.subject_id AND a.hadm_id = lm.hadm_id

UNION ALL

SELECT
  'Control Patients' AS group_type,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  AVG(CASE WHEN li.abnormal_lab_count > 0 THEN li.abnormal_lab_count * 1.0 / li.total_lab_tests ELSE 0 END) AS mean_lab_instability_score,
  AVG(ce.icu_stays) AS avg_icu_stays,
  AVG(ce.procedure_count) AS avg_procedure_count,
  AVG(ce.medication_count) AS avg_medication_count,
  AVG(lm.length_of_stay_days) AS avg_length_of_stay,
  SUM(lm.in_hospital_mortality) * 1.0 / COUNT(DISTINCT c.subject_id) AS mortality_rate
FROM
  control_patients c
LEFT JOIN
  lab_instability li ON c.subject_id = li.subject_id AND c.hadm_id = li.hadm_id
LEFT JOIN
  critical_events ce ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id
LEFT JOIN
  los_mortality lm ON c.subject_id = lm.subject_id AND c.hadm_id = lm.hadm_id;