WITH
-- Get male patients aged 87-97
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 87 AND 97
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (EXTRACT(DATE FROM a.dischtime) - EXTRACT(DATE FROM a.admittime)) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
),

-- Identify ACS patients (ICD-10 codes I20-I25)
acs_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code
  WHERE
    d.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND di.icd_code LIKE 'I2%'
),

-- Get lab events within first 72 hours of admission
early_lab_events AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    d.label,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  JOIN
    patient_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
),

-- Calculate lab instability score (simplified example)
lab_instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(CASE
      WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
      ELSE 0
    END) AS instability_score
  FROM
    early_lab_events
  GROUP BY
    subject_id, hadm_id
),

-- Calculate 95th percentile of instability scores
percentile_calc AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_score
  FROM
    lab_instability_scores
  LIMIT 1
),

-- Get patients with scores >= 95th percentile
high_risk_patients AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.instability_score,
    a.los_days,
    a.hospital_expire_flag
  FROM
    lab_instability_scores l
  JOIN
    patient_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  CROSS JOIN
    percentile_calc p
  WHERE
    l.instability_score >= p.p95_score
),

-- Calculate average critical lab events for high-risk vs general patients
lab_event_comparison AS (
  SELECT
    'High Risk' AS patient_group,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(l.labevent_id) / COUNT(DISTINCT l.subject_id) AS avg_lab_events_per_patient
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    high_risk_patients h ON l.subject_id = h.subject_id AND l.hadm_id = h.hadm_id
  JOIN
    patient_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)

  UNION ALL

  SELECT
    'General' AS patient_group,
    COUNT(DISTINCT l.subject_id) AS patient_count,
    COUNT(l.labevent_id) / COUNT(DISTINCT l.subject_id) AS avg_lab_events_per_patient
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    patient_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
)

-- Final results
SELECT
  '95th Percentile Lab Instability Score' AS metric,
  CAST(p.p95_score AS STRING) AS value
FROM
  percentile_calc p

UNION ALL

SELECT
  'Mean LOS for High Risk Patients (days)' AS metric,
  CAST(AVG(CAST(h.los_days AS FLOAT64)) AS STRING) AS value
FROM
  high_risk_patients h

UNION ALL

SELECT
  'In-Hospital Mortality for High Risk Patients (%)' AS metric,
  CAST(ROUND(100 * SUM(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(h.subject_id), 2) AS STRING) AS value
FROM
  high_risk_patients h

UNION ALL

SELECT
  'Average Lab Events Comparison' AS metric,
  STRING_AGG(CONCAT(l.patient_group, ': ', ROUND(l.avg_lab_events_per_patient, 2)), ', ') AS value
FROM
  lab_event_comparison l;