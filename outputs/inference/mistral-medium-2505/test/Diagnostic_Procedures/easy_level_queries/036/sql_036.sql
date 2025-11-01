WITH
-- Get male patients aged 42-52 at admission
male_patients_42_52 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission (anchor_age is age at first admission)
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 42 AND 52
),

-- Get valve repair/replacement procedures (ICD-9 codes 35.xx)
valve_procedures AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    d.long_title AS procedure_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
  WHERE
    -- Filter for valve repair/replacement procedures (ICD-9 35.xx)
    (pr.icd_version = 9 AND pr.icd_code LIKE '35%')
    OR
    -- Include ICD-10 equivalents if needed (e.g., 02RF, 02RG, etc.)
    (pr.icd_version = 10 AND pr.icd_code IN ('02RF', '02RG', '02RH', '02RJ', '02RK', '02RL'))
),

-- Count distinct valve procedures per patient
patient_valve_procedure_counts AS (
  SELECT
    vp.subject_id,
    COUNT(DISTINCT icd_code) AS distinct_valve_procedures
  FROM
    valve_procedures vp
  JOIN
    male_patients_42_52 mp
  ON
    vp.subject_id = mp.subject_id
  GROUP BY
    vp.subject_id
)

-- Calculate average distinct valve procedures per patient
SELECT
  AVG(distinct_valve_procedures) AS avg_distinct_valve_procedures_per_patient
FROM
  patient_valve_procedure_counts;