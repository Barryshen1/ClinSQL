WITH target_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
),

diabetes_hf_admissions AS (
  SELECT
    tp.hadm_id,
    tp.admittime,
    tp.dischtime
  FROM
    target_patients tp
  WHERE
    EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = tp.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(dd.icd_code, r'^250'))
          OR
          (d.icd_version = 10 AND REGEXP_CONTAINS(dd.icd_code, r'^E0[8-9]|^E1[0-3]'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = tp.hadm_id
        AND (
          (d.icd_version = 9 AND REGEXP_CONTAINS(dd.icd_code, r'^428'))
          OR
          (d.icd_version = 10 AND REGEXP_CONTAINS(dd.icd_code, r'^I50'))
        )
    )
),

glp1_medications AS (
  SELECT
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS drug
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE
    REGEXP_CONTAINS(LOWER(drug), r'(exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide)')
),

first_48hr_use AS (
  SELECT DISTINCT
    dha.hadm_id
  FROM
    diabetes_hf_admissions dha
  JOIN
    glp1_medications g
    ON dha.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN dha.admittime AND TIMESTAMP_ADD(dha.admittime, INTERVAL 48 HOUR)
),

last_24hr_use AS (
  SELECT DISTINCT
    dha.hadm_id
  FROM
    diabetes_hf_admissions dha
  JOIN
    glp1_medications g
    ON dha.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN TIMESTAMP_SUB(dha.dischtime, INTERVAL 24 HOUR) AND dha.dischtime
),

counts AS (
  SELECT
    COUNT(DISTINCT dha.hadm_id) AS total_admissions,
    COUNT(DISTINCT f48.hadm_id) AS first_48hr_users,
    COUNT(DISTINCT l24.hadm_id) AS last_24hr_users
  FROM
    diabetes_hf_admissions dha
  LEFT JOIN
    first_48hr_use f48
    ON dha.hadm_id = f48.hadm_id
  LEFT JOIN
    last_24hr_use l24
    ON dha.hadm_id = l24.hadm_id
)

SELECT
  ROUND(100 * first_48hr_users / total_admissions, 2) AS first_48hr_prevalence_pct,
  ROUND(100 * last_24hr_users / total_admissions, 2) AS last_24hr_prevalence_pct,
  ROUND(100 * (last_24hr_users - first_48hr_users) / total_admissions, 2) AS net_change_pct
FROM
  counts;