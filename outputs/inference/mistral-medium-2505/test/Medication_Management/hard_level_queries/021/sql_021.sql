WITH
-- Get male patients aged 41-51
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_patients p ON a.subject_id = p.subject_id
),

-- Identify patients with neutropenia (using WBC < 1.5 as proxy)
neutropenic_patients AS (
  SELECT DISTINCT
    le.subject_id,
    le.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE
    dli.label LIKE '%WBC%' OR dli.label LIKE '%Neutrophil%'
    AND le.valuenum < 1.5  -- Neutropenia threshold
    AND le.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Identify patients with fever (temperature > 38°C)
febrile_patients AS (
  SELECT DISTINCT
    ce.subject_id,
    ce.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    (di.label LIKE '%Temperature%' OR di.label LIKE '%Temp%')
    AND ce.valuenum > 38  -- Fever threshold
    AND ce.valueuom = '°C'
    AND ce.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Get patients with both neutropenia and fever
target_patients AS (
  SELECT
    np.subject_id,
    np.hadm_id
  FROM
    neutropenic_patients np
  JOIN
    febrile_patients fp ON np.subject_id = fp.subject_id AND np.hadm_id = fp.hadm_id
),

-- Count unique medications in first 48 hours
medication_counts AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS unique_med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    target_patients tp ON p.subject_id = tp.subject_id AND p.hadm_id = tp.hadm_id
  JOIN
    patient_admissions pa ON p.subject_id = pa.subject_id AND p.hadm_id = pa.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.starttime, pa.admittime, HOUR) <= 48
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Calculate tertiles for medication counts
medication_tertiles AS (
  SELECT
    subject_id,
    hadm_id,
    unique_med_count,
    NTILE(3) OVER (ORDER BY unique_med_count) AS tertile
  FROM
    medication_counts
),

-- Calculate 30-day readmission
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    patient_admissions a1
  LEFT JOIN
    patient_admissions a2 ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
    AND a1.hadm_id != a2.hadm_id
  WHERE
    a1.subject_id IN (SELECT subject_id FROM target_patients)
)

-- Final results
SELECT
  mt.tertile,
  COUNT(DISTINCT mt.subject_id) AS patient_count,
  AVG(pa.los_days) AS avg_los_days,
  SUM(pa.hospital_expire_flag) * 100.0 / COUNT(DISTINCT mt.subject_id) AS in_hospital_mortality_pct,
  SUM(r.readmitted_30d) * 100.0 / COUNT(DISTINCT mt.subject_id) AS readmission_30d_pct
FROM
  medication_tertiles mt
JOIN
  patient_admissions pa ON mt.subject_id = pa.subject_id AND mt.hadm_id = pa.hadm_id
JOIN
  readmissions r ON mt.subject_id = r.subject_id AND mt.hadm_id = r.original_hadm_id
GROUP BY
  mt.tertile
ORDER BY
  mt.tertile;