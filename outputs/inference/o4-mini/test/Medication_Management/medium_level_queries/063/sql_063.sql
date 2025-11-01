WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- male, age 45–55
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    -- Diabetes diagnosis
    JOIN (
      SELECT DISTINCT subject_id, hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%diabetes%'
    ) diag_dm
      ON a.subject_id = diag_dm.subject_id
     AND a.hadm_id = diag_dm.hadm_id
    -- Heart failure diagnosis
    JOIN (
      SELECT DISTINCT subject_id, hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%heart failure%'
    ) diag_hf
      ON a.subject_id = diag_hf.subject_id
     AND a.hadm_id = diag_hf.hadm_id
),
presc_flags AS (
  SELECT
    c.hadm_id,
    -- First 12h window
    MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%'
              AND p.starttime BETWEEN c.admittime
                               AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS insulin_first,
    MAX(CASE WHEN p.drug_type = 'ORAL'
              AND p.starttime BETWEEN c.admittime
                               AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS oral_first,
    -- Final 72h window
    MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%'
              AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
                               AND c.dischtime
             THEN 1 ELSE 0 END) AS insulin_final,
    MAX(CASE WHEN p.drug_type = 'ORAL'
              AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
                               AND c.dischtime
             THEN 1 ELSE 0 END) AS oral_final
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.subject_id = p.subject_id
     AND c.hadm_id = p.hadm_id
  GROUP BY
    c.hadm_id
),
summary AS (
  SELECT
    COUNT(1)                        AS total_admissions,
    SUM(insulin_first)             AS n_insulin_first,
    SUM(insulin_final)             AS n_insulin_final,
    SUM(oral_first)                AS n_oral_first,
    SUM(oral_final)                AS n_oral_final
  FROM
    presc_flags
)
SELECT
  total_admissions                                       AS N,
  ROUND(100.0 * n_insulin_first  / total_admissions, 1) AS insulin_first_pct,
  ROUND(100.0 * n_insulin_final  / total_admissions, 1) AS insulin_final_pct,
  ROUND(100.0 * n_insulin_first  / total_admissions
        - 100.0 * n_insulin_final / total_admissions, 1) AS insulin_pp_diff,
  ROUND(100.0 * n_oral_first     / total_admissions, 1) AS oral_first_pct,
  ROUND(100.0 * n_oral_final     / total_admissions, 1) AS oral_final_pct,
  ROUND(100.0 * n_oral_first     / total_admissions
        - 100.0 * n_oral_final   / total_admissions, 1) AS oral_pp_diff
FROM
  summary;