WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    -- Compute birth year: anchor_year - anchor_age
    (p.anchor_year - p.anchor_age) AS birth_year,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 84 AND 94
),
echocardiography_procedures AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_echocardiography_procedures
  FROM
    patient_admissions pa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pa.subject_id = pr.subject_id
    AND pa.hadm_id = pr.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
    AND d.icd_version = 9  -- procedures_icd uses ICD-9
    AND LOWER(d.long_title) LIKE '%echocardiography%'
  GROUP BY
    pa.hadm_id
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY distinct_echocardiography_procedures) AS p25_distinct_echocardiography_per_hadm
FROM
  echocardiography_procedures;