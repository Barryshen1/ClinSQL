WITH
-- Get male patients aged 61-71
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 61 AND 71
),

-- Get admissions with hemorrhagic stroke (ICD-10 I61.*)
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I61.%'
    AND d.icd_version = 10
),

-- Calculate medication complexity score (number of unique medications in first 24 hours)
med_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    stroke_admissions a
  ON
    p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.starttime, a.admittime, HOUR) <= 24
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los_days,
    a.hospital_expire_flag,
    m.complexity_score,
    -- Calculate 30-day readmission flag
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
      AND a2.admittime > a.dischtime
      AND TIMESTAMP_DIFF(a2.admittime, a.dischtime, DAY) <= 30
    ) AS readmitted_30d
  FROM
    patient_demo p
  JOIN
    stroke_admissions a
  ON
    p.subject_id = a.subject_id
  JOIN
    med_complexity m
  ON
    a.subject_id = m.subject_id AND a.hadm_id = m.hadm_id
),

-- Create quintiles based on complexity score
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM
    combined_data
)

-- Final aggregation by quintile
SELECT
  quintile,
  COUNT(DISTINCT subject_id) AS num_patients,
  ROUND(AVG(complexity_score), 2) AS mean_complexity_score,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS in_hospital_mortality_pct,
  ROUND(100 * SUM(CASE WHEN readmitted_30d THEN 1 ELSE 0 END) / COUNT(*), 2) AS readmission_30d_pct
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;