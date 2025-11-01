WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Compute birth year: anchor_year - anchor_age
    (p.anchor_year - p.anchor_age) AS birth_year,
    -- Age at admission: year of admittime minus birth_year
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 57 AND 67
),
valve_procedures AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_valve_procedures
  FROM
    patient_admissions pa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    pa.subject_id = pr.subject_id
    AND pa.hadm_id = pr.hadm_id
    AND pr.icd_version = 9  -- ICD-9-CM
    AND pr.icd_code LIKE '35.%'  -- Valve procedures
  GROUP BY
    pa.hadm_id
)
SELECT
  MIN(distinct_valve_procedures) AS min_distinct_valve_procedures
FROM
  valve_procedures;