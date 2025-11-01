WITH
-- Get male patients aged 58-68
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),

-- Get admissions with length ≥72 hours
long_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_length_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- Identify patients with T2DM and heart failure
t2dm_hf_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    long_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code
  WHERE
    -- T2DM ICD-10 codes (E11.*)
    (d.icd_code LIKE 'E11%' OR d.icd_code LIKE '250.%')
    -- Heart failure ICD-10 codes (I50.*, I11.0, I13.0, I13.2)
    OR (d.icd_code LIKE 'I50%' OR d.icd_code IN ('I11.0', 'I13.0', 'I13.2'))
  GROUP BY
    a.subject_id, a.hadm_id
  HAVING
    -- Must have both T2DM and heart failure
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'E11%' OR d.icd_code LIKE '250.%' THEN d.icd_code END) > 0
    AND COUNT(DISTINCT CASE WHEN d.icd_code LIKE 'I50%' OR d.icd_code IN ('I11.0', 'I13.0', 'I13.2') THEN d.icd_code END) > 0
),

-- Identify GLP-1 agonist prescriptions
glp1_prescriptions AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    t2dm_hf_patients t ON p.hadm_id = t.hadm_id
  WHERE
    -- Common GLP-1 agonist names (case-insensitive)
    LOWER(p.drug) LIKE '%exenatide%'
    OR LOWER(p.drug) LIKE '%liraglutide%'
    OR LOWER(p.drug) LIKE '%dulaglutide%'
    OR LOWER(p.drug) LIKE '%semaglutide%'
    OR LOWER(p.drug) LIKE '%lixisenatide%'
    OR LOWER(p.drug) LIKE '%albiglutide%'
),

-- Calculate first 72 hours starts
first_72h_starts AS (
  SELECT
    COUNT(DISTINCT g.subject_id) AS count
  FROM
    glp1_prescriptions g
  JOIN
    long_admissions a ON g.hadm_id = a.hadm_id
  WHERE
    TIMESTAMP_DIFF(g.starttime, a.admittime, HOUR) BETWEEN 0 AND 72
),

-- Calculate final 12 hours starts
final_12h_starts AS (
  SELECT
    COUNT(DISTINCT g.subject_id) AS count
  FROM
    glp1_prescriptions g
  JOIN
    long_admissions a ON g.hadm_id = a.hadm_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, g.starttime, HOUR) BETWEEN 0 AND 12
),

-- Total eligible patients
total_patients AS (
  SELECT
    COUNT(DISTINCT subject_id) AS count
  FROM
    t2dm_hf_patients
)

-- Final results
SELECT
  (SELECT count FROM first_72h_starts) AS first_72h_count,
  (SELECT count FROM final_12h_starts) AS final_12h_count,
  (SELECT count FROM total_patients) AS total_patients,
  ROUND((SELECT count FROM first_72h_starts) * 100.0 / (SELECT count FROM total_patients), 2) AS first_72h_percentage,
  ROUND((SELECT count FROM final_12h_starts) * 100.0 / (SELECT count FROM total_patients), 2) AS final_12h_percentage,
  ROUND(
    ((SELECT count FROM first_72h_starts) * 100.0 / (SELECT count FROM total_patients)) -
    ((SELECT count FROM final_12h_starts) * 100.0 / (SELECT count FROM total_patients)),
    2
  ) AS absolute_difference_pp;