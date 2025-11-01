WITH
-- Define the cohort of male inpatients aged 56-66 with diabetes and heart failure
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.admission_type = 'ELECTIVE' -- or other appropriate admission types
    AND a.hospital_expire_flag = 0 -- exclude patients who died in hospital
    AND EXISTS (
      -- Diabetes diagnosis (ICD-10: E11.* or ICD-9: 250.*)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 10 AND d.icd_code LIKE 'E11%') OR
          (diag.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      -- Heart failure diagnosis (ICD-10: I50.* or ICD-9: 428.*)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE diag.subject_id = p.subject_id
        AND diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 10 AND d.icd_code LIKE 'I50%') OR
          (diag.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),

-- Identify GLP-1 receptor agonist prescriptions
glp1_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%glp-1%'
    OR LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
    OR LOWER(drug) LIKE '%albiglutide%'
),

-- Calculate first 48 hours GLP-1 use
first_48h_use AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN g.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS used_in_first_48h
  FROM
    cohort c
  LEFT JOIN
    glp1_prescriptions g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id
),

-- Calculate final 24 hours GLP-1 use
final_24h_use AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN g.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS used_in_final_24h
  FROM
    cohort c
  LEFT JOIN
    glp1_prescriptions g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id
),

-- Combine results
combined_results AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    f.used_in_first_48h,
    l.used_in_final_24h
  FROM
    cohort c
  JOIN
    first_48h_use f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  JOIN
    final_24h_use l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
)

-- Final aggregation
SELECT
  COUNT(*) AS total_patients,
  SUM(used_in_first_48h) AS first_48h_count,
  ROUND(SUM(used_in_first_48h) * 100.0 / COUNT(*), 2) AS first_48h_prevalence,
  SUM(used_in_final_24h) AS final_24h_count,
  ROUND(SUM(used_in_final_24h) * 100.0 / COUNT(*), 2) AS final_24h_prevalence,
  ROUND((SUM(used_in_final_24h) - SUM(used_in_first_48h)) * 100.0 / COUNT(*), 2) AS net_change_prevalence
FROM
  combined_results;