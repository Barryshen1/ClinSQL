WITH
-- Define our cohort of male inpatients 79-89 with type 2 diabetes and heart failure
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      (d1.icd_code LIKE 'E11.%' OR d1.icd_code LIKE '250.%' OR d1.icd_code LIKE 'E11%' OR d1.icd_code LIKE '250%')
      AND
      (d2.icd_code LIKE 'I50.%' OR d2.icd_code LIKE '428.%' OR d2.icd_code LIKE 'I50%' OR d2.icd_code LIKE '428%')
    )
),

-- Identify GLP-1 agonist prescriptions
glp1_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%albiglutide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
),

-- Patients who initiated GLP-1 in first 12 hours
early_initiators AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    glp1_prescriptions g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
),

-- Patients who initiated GLP-1 in last 24 hours
late_initiators AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
  JOIN
    glp1_prescriptions g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  WHERE
    g.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
),

-- Counts for each group
counts AS (
  SELECT
    COUNT(DISTINCT c.subject_id) AS total_patients,
    COUNT(DISTINCT e.subject_id) AS early_initiators,
    COUNT(DISTINCT l.subject_id) AS late_initiators
  FROM
    cohort c
  LEFT JOIN
    early_initiators e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  LEFT JOIN
    late_initiators l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
)

-- Final calculation with NULL checks
SELECT
  total_patients,
  early_initiators,
  CASE
    WHEN total_patients = 0 THEN NULL
    ELSE ROUND(early_initiators * 100.0 / total_patients, 2)
  END AS percent_early_initiators,
  late_initiators,
  CASE
    WHEN total_patients = 0 THEN NULL
    ELSE ROUND(late_initiators * 100.0 / total_patients, 2)
  END AS percent_late_initiators,
  CASE
    WHEN total_patients = 0 THEN NULL
    ELSE ROUND((late_initiators * 100.0 / total_patients) - (early_initiators * 100.0 / total_patients), 2)
  END AS net_percentage_point_change
FROM
  counts;