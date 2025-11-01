WITH
-- Define AMI patients (ICD-10 codes for AMI: I21.x, I22.x)
ami_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    AND d.icd_version = 10
),

-- Define age-matched non-AMI patients
non_ami_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS hospital_los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND a.subject_id NOT IN (SELECT subject_id FROM ami_patients)
),

-- Get ICU stays for both groups
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    'AMI' AS cohort
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ami_patients a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id

  UNION ALL

  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    'Non-AMI' AS cohort
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    non_ami_patients n ON i.subject_id = n.subject_id AND i.hadm_id = n.hadm_id
),

-- Get procedures in first 72 hours of ICU stay
icu_procedures AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.cohort,
    COUNT(DISTINCT p.itemid) AS distinct_procedures
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON i.subject_id = p.subject_id
    AND i.hadm_id = p.hadm_id
    AND i.stay_id = p.stay_id
    AND p.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id, i.cohort
),

-- Get hospital procedures in first 72 hours of ICU stay
hospital_procedures AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.cohort,
    COUNT(DISTINCT p.icd_code) AS distinct_hospital_procedures
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON i.subject_id = p.subject_id
    AND i.hadm_id = p.hadm_id
    AND p.chartdate BETWEEN DATE(i.intime) AND DATE(TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR))
  GROUP BY
    i.subject_id, i.hadm_id, i.stay_id, i.cohort
),

-- Combine procedure counts
combined_procedures AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.cohort,
    COALESCE(ip.distinct_procedures, 0) + COALESCE(hp.distinct_hospital_procedures, 0) AS total_distinct_procedures
  FROM
    icu_stays i
  LEFT JOIN
    icu_procedures ip ON i.subject_id = ip.subject_id AND i.hadm_id = ip.hadm_id AND i.stay_id = ip.stay_id
  LEFT JOIN
    hospital_procedures hp ON i.subject_id = hp.subject_id AND i.hadm_id = hp.hadm_id AND i.stay_id = hp.stay_id
),

-- Calculate percentiles and metrics
final_metrics AS (
  SELECT
    cohort,
    APPROX_QUANTILES(total_distinct_procedures, 100)[OFFSET(90)] AS percentile_90,
    AVG(hospital_los_days) AS avg_hospital_los,
    SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
  FROM
    combined_procedures cp
  JOIN
    (SELECT subject_id, hadm_id, hospital_los_days, hospital_expire_flag FROM ami_patients
     UNION ALL
     SELECT subject_id, hadm_id, hospital_los_days, hospital_expire_flag FROM non_ami_patients) h
    ON cp.subject_id = h.subject_id AND cp.hadm_id = h.hadm_id
  GROUP BY
    cohort
)

-- Final output
SELECT * FROM final_metrics
ORDER BY cohort;