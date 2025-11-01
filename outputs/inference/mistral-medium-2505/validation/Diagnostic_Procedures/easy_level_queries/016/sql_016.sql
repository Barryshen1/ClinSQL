WITH female_patients_75_85 AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 75 AND 85
),

admissions_for_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients_75_85 p ON a.subject_id = p.subject_id
),

ecg_telemetry_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS distinct_ecg_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    admissions_for_patients a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    -- Example ICD-9 codes for ECG/telemetry (adjust as needed)
    p.icd_code IN ('89.41', '89.42', '89.43', '89.44', '89.45', '89.46', '89.47', '89.48', '89.49')
    OR
    -- Example ICD-10 codes for ECG/telemetry (adjust as needed)
    p.icd_code IN ('Z01.818', 'Z01.819', 'Z01.820', 'Z01.821', 'Z01.822', 'Z01.823', 'Z01.824', 'Z01.825', 'Z01.826', 'Z01.827', 'Z01.828')
  GROUP BY
    p.subject_id, p.hadm_id
)

SELECT
  PERCENTILE_CONT(distinct_ecg_procedures, 0.75) OVER() AS percentile_75
FROM
  ecg_telemetry_procedures
LIMIT 1;