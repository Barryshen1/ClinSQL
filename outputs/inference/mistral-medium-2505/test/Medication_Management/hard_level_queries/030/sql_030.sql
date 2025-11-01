WITH
-- Identify female patients aged 71-81 with acute pancreatitis
pancreatitis_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND di.icd_code LIKE 'K85.%'  -- Acute pancreatitis ICD-10 codes
    AND a.admission_type != 'NEWBORN'  -- Exclude newborn admissions
),

-- Calculate medication complexity score for first 72 hours
medication_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    -- Count of unique medications
    COUNT(DISTINCT ph.medication) AS unique_med_count,
    -- Count of medication administrations
    COUNT(*) AS total_med_admin,
    -- Count of different routes
    COUNT(DISTINCT ph.route) AS route_count,
    -- Count of different frequencies
    COUNT(DISTINCT ph.frequency) AS frequency_count,
    -- Complexity score (weighted sum)
    (COUNT(DISTINCT ph.medication) * 0.3 +
     COUNT(*) * 0.2 +
     COUNT(DISTINCT ph.route) * 0.25 +
     COUNT(DISTINCT ph.frequency) * 0.25) AS complexity_score
  FROM
    pancreatitis_patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON p.hadm_id = ph.hadm_id
  WHERE
    -- First 72 hours of admission
    ph.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
    AND ph.medication IS NOT NULL
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Add tertiles to complexity scores
complexity_tertiles AS (
  SELECT
    subject_id,
    hadm_id,
    complexity_score,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM
    medication_complexity
),

-- Calculate 30-day readmission
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS index_hadm_id,
    a2.hadm_id AS readmit_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE
    a2.admittime > a1.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
    AND a2.admission_type != 'NEWBORN'
),

-- Final dataset with all metrics
final_dataset AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los_days,
    c.tertile,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_30day_readmission
  FROM
    pancreatitis_patients p
  JOIN
    complexity_tertiles c ON p.hadm_id = c.hadm_id
  LEFT JOIN
    readmissions r ON p.hadm_id = r.index_hadm_id
)

-- Final results stratified by tertile
SELECT
  tertile,
  COUNT(*) AS patient_count,
  AVG(los_days) AS avg_los,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate,
  SUM(had_30day_readmission) / COUNT(*) AS readmission_rate
FROM
  final_dataset
GROUP BY
  tertile
ORDER BY
  tertile;