WITH
-- Define age range and gender filter
patient_filter AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 48 AND 58
),

-- Get admissions for these patients
admissions_with_diabetes_hf AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_filter p ON a.subject_id = p.subject_id
  WHERE
    EXISTS (
      -- Type 2 diabetes diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND di.icd_code LIKE 'E11.%') OR
          (d.icd_version = 9 AND di.icd_code BETWEEN '250.00' AND '250.93')
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND di.icd_code LIKE 'I50.%') OR
          (d.icd_version = 9 AND di.icd_code LIKE '428.%')
        )
    )
),

-- Identify GLP-1 receptor agonist administrations
glp1_administrations AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    -- Check prescriptions table
    CASE WHEN p.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_glp1_prescription,
    -- Check pharmacy table
    CASE WHEN ph.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_glp1_pharmacy,
    -- Check emar table
    CASE WHEN e.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_glp1_emar,
    -- Get first administration time
    COALESCE(
      (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.emar` WHERE hadm_id = a.hadm_id AND LOWER(medication) LIKE '%glp-1%'),
      (SELECT MIN(starttime) FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` WHERE hadm_id = a.hadm_id AND LOWER(medication) LIKE '%glp-1%'),
      (SELECT MIN(starttime) FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` WHERE hadm_id = a.hadm_id AND LOWER(drug) LIKE '%glp-1%')
    ) AS first_glp1_time
  FROM
    admissions_with_diabetes_hf a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.hadm_id = p.hadm_id
    AND LOWER(p.drug) LIKE '%glp-1%'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON a.hadm_id = ph.hadm_id
    AND LOWER(ph.medication) LIKE '%glp-1%'
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
    ON a.hadm_id = e.hadm_id
    AND LOWER(e.medication) LIKE '%glp-1%'
),

-- Calculate time windows
time_windows AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR) AS first_12h_end,
    TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR) AS final_12h_start,
    g.first_glp1_time,
    CASE WHEN g.first_glp1_time BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR) THEN TRUE ELSE FALSE END AS in_first_12h,
    CASE WHEN g.first_glp1_time BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 12 HOUR) AND a.dischtime THEN TRUE ELSE FALSE END AS in_final_12h
  FROM
    admissions_with_diabetes_hf a
  LEFT JOIN
    glp1_administrations g ON a.hadm_id = g.hadm_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 24 -- Only include admissions with at least 24h stay
)

-- Final aggregation
SELECT
  COUNT(DISTINCT hadm_id) AS total_admissions,
  SUM(CASE WHEN in_first_12h THEN 1 ELSE 0 END) AS first_12h_count,
  SUM(CASE WHEN in_final_12h THEN 1 ELSE 0 END) AS final_12h_count,
  ROUND(SUM(CASE WHEN in_first_12h THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS first_12h_percentage,
  ROUND(SUM(CASE WHEN in_final_12h THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS final_12h_percentage,
  ROUND(
    (SUM(CASE WHEN in_final_12h THEN 1 ELSE 0 END) - SUM(CASE WHEN in_first_12h THEN 1 ELSE 0 END)) * 100.0 / COUNT(DISTINCT hadm_id),
    2
  ) AS net_change_percentage
FROM
  time_windows;