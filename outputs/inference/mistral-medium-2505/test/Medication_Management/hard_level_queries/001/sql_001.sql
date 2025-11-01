WITH
-- Get female patients aged 76-86
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get cardiac arrest admissions (using ICD-10 codes for cardiac arrest)
cardiac_arrest_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code IN ('I46.9', 'I46.2', 'I46.0', 'I46.1') -- Cardiac arrest ICD-10 codes
    AND d.icd_version = '10'
),

-- Get medication complexity (count of distinct medications in first 7 days)
medication_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS medication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    cardiac_arrest_admissions a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 7 DAY)
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Calculate quintiles for medication complexity
quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    medication_count,
    NTILE(5) OVER (ORDER BY medication_count) AS quintile
  FROM
    medication_complexity
),

-- Calculate 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmission_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  JOIN
    cardiac_arrest_admissions ca
    ON a1.hadm_id = CAST(ca.hadm_id AS INT64)  -- Fixed: Explicit cast to INT64
)

-- Final aggregated results
SELECT
  q.quintile,
  COUNT(DISTINCT q.subject_id) AS patient_count,
  AVG(mc.medication_count) AS avg_medication_score,
  MIN(mc.medication_count) AS min_medication_score,
  MAX(mc.medication_count) AS max_medication_score,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id) AS in_hospital_mortality_pct,
  SUM(CASE WHEN r.readmission_hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT q.subject_id) AS thirty_day_readmission_pct
FROM
  quintiles q
JOIN
  medication_complexity mc ON q.subject_id = mc.subject_id AND q.hadm_id = mc.hadm_id
JOIN
  cardiac_arrest_admissions a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
LEFT JOIN
  readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.original_hadm_id
GROUP BY
  q.quintile
ORDER BY
  q.quintile;