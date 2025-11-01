WITH
-- Define medication classes and their identifiers
medication_classes AS (
  SELECT 'Metformin' AS class, 'metformin' AS drug_pattern UNION ALL
  SELECT 'Sulfonylureas', 'sulfonylurea' UNION ALL
  SELECT 'DPP-4 inhibitors', 'dpp-4' UNION ALL
  SELECT 'SGLT2 inhibitors', 'sglt2'
),

-- Get female patients aged 68-78
eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS total_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Get all medications administered
all_medications AS (
  SELECT
    e.hadm_id,
    LOWER(p.medication) AS medication_name,
    p.starttime,
    p.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` p
  JOIN
    eligible_patients e ON p.hadm_id = e.hadm_id
  UNION DISTINCT
  SELECT
    e.hadm_id,
    LOWER(pr.drug) AS medication_name,
    pr.starttime,
    pr.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    eligible_patients e ON pr.hadm_id = e.hadm_id
),

-- Classify medications
classified_medications AS (
  SELECT
    a.hadm_id,
    a.medication_name,
    a.starttime,
    a.stoptime,
    m.class
  FROM
    all_medications a
  JOIN
    medication_classes m ON LOWER(a.medication_name) LIKE '%' || LOWER(m.drug_pattern) || '%'
),

-- First 48 hours medications
first_48h_meds AS (
  SELECT
    e.hadm_id,
    c.class,
    MAX(CASE WHEN c.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS has_medication
  FROM
    eligible_patients e
  LEFT JOIN
    classified_medications c ON e.hadm_id = c.hadm_id
  GROUP BY
    e.hadm_id, c.class
),

-- Last 12 hours medications
last_12h_meds AS (
  SELECT
    e.hadm_id,
    c.class,
    MAX(CASE WHEN c.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR) AND e.dischtime THEN 1 ELSE 0 END) AS has_medication
  FROM
    eligible_patients e
  LEFT JOIN
    classified_medications c ON e.hadm_id = c.hadm_id
  GROUP BY
    e.hadm_id, c.class
),

-- Aggregate results
aggregated_results AS (
  SELECT
    m.class,
    COUNT(DISTINCT e.hadm_id) AS total_patients,
    SUM(f.has_medication) AS first_48h_count,
    SUM(l.has_medication) AS last_12h_count
  FROM
    eligible_patients e
  CROSS JOIN
    (SELECT DISTINCT class FROM medication_classes) m
  LEFT JOIN
    first_48h_meds f ON e.hadm_id = f.hadm_id AND m.class = f.class
  LEFT JOIN
    last_12h_meds l ON e.hadm_id = l.hadm_id AND m.class = l.class
  GROUP BY
    m.class
)

-- Final calculation
SELECT
  class,
  ROUND((first_48h_count / total_patients) * 100, 2) AS first_48h_prevalence,
  ROUND((last_12h_count / total_patients) * 100, 2) AS last_12h_prevalence,
  ROUND(((last_12h_count / total_patients) - (first_48h_count / total_patients)) * 100, 2) AS net_change_pp
FROM
  aggregated_results
ORDER BY
  class;