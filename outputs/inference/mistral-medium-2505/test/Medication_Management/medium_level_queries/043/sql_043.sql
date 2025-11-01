WITH
-- Define age range and gender
male_patients_77_87 AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_patients_77_87 p ON a.subject_id = p.subject_id
  WHERE
    a.hospital_expire_flag = 0
),

-- Identify patients with diabetes and heart failure
patients_with_conditions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime
  FROM
    patient_admissions pa
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        di.subject_id = pa.subject_id
        AND di.hadm_id = pa.hadm_id
        AND (
          -- Diabetes (ICD-10 E11-E14)
          (d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
          -- Heart failure (ICD-10 I50.x)
          OR d.icd_code LIKE 'I50%'
        )
    )
  GROUP BY
    pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime
),

-- Define drug classes
drug_classes AS (
  SELECT
    'Antidiabetics' AS drug_class,
    'metformin' AS drug_name UNION ALL
  SELECT
    'Antidiabetics',
    'insulin' UNION ALL
  SELECT
    'Beta-blockers',
    'metoprolol' UNION ALL
  SELECT
    'Beta-blockers',
    'carvedilol' UNION ALL
  SELECT
    'ACEi/ARB/ARNI',
    'lisinopril' UNION ALL
  SELECT
    'ACEi/ARB/ARNI',
    'losartan' UNION ALL
  SELECT
    'ACEi/ARB/ARNI',
    'sacubitril/valsartan' UNION ALL
  SELECT
    'Loop diuretics',
    'furosemide'
),

-- Get prescriptions with drug classification
classified_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    dc.drug_class,
    dc.drug_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    drug_classes dc
    ON LOWER(p.drug) LIKE '%' || LOWER(dc.drug_name) || '%'
  WHERE
    p.subject_id IN (SELECT subject_id FROM patients_with_conditions)
),

-- Calculate time windows
time_windows AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS last_12h_start
  FROM
    patients_with_conditions
),

-- Count initiations in first 48h
first_48h_initiations AS (
  SELECT
    cp.drug_class,
    COUNT(DISTINCT cp.subject_id) AS patient_count,
    COUNT(DISTINCT cp.hadm_id) AS admission_count
  FROM
    classified_prescriptions cp
  JOIN
    time_windows tw ON cp.subject_id = tw.subject_id AND cp.hadm_id = tw.hadm_id
  WHERE
    cp.starttime BETWEEN tw.admittime AND tw.first_48h_end
  GROUP BY
    cp.drug_class
),

-- Count initiations in last 12h
last_12h_initiations AS (
  SELECT
    cp.drug_class,
    COUNT(DISTINCT cp.subject_id) AS patient_count,
    COUNT(DISTINCT cp.hadm_id) AS admission_count
  FROM
    classified_prescriptions cp
  JOIN
    time_windows tw ON cp.subject_id = tw.subject_id AND cp.hadm_id = tw.hadm_id
  WHERE
    cp.starttime BETWEEN tw.last_12h_start AND tw.dischtime
  GROUP BY
    cp.drug_class
),

-- Total patients and admissions for reference
total_counts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    patients_with_conditions
)

-- Final results
SELECT
  dc.drug_class,
  f48.patient_count AS first_48h_patient_count,
  ROUND(f48.patient_count * 100.0 / tc.total_patients, 2) AS first_48h_patient_percentage,
  l12.patient_count AS last_12h_patient_count,
  ROUND(l12.patient_count * 100.0 / tc.total_patients, 2) AS last_12h_patient_percentage,
  ROUND((l12.patient_count - f48.patient_count) * 100.0 / tc.total_patients, 2) AS net_change_percentage
FROM
  drug_classes dc
LEFT JOIN
  first_48h_initiations f48 ON dc.drug_class = f48.drug_class
LEFT JOIN
  last_12h_initiations l12 ON dc.drug_class = l12.drug_class
CROSS JOIN
  total_counts tc
ORDER BY
  dc.drug_class;