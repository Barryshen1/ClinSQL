WITH
-- Identify 87-year-old female patients with hemorrhagic stroke
stroke_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 87
    AND (
      -- ICD-9 codes for hemorrhagic stroke
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      -- ICD-10 codes for hemorrhagic stroke
      (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
    )
),

-- Get discharge dates for these patients
discharge_dates AS (
  SELECT
    s.subject_id,
    a.hadm_id,
    DATE(a.dischtime) AS discharge_date
  FROM
    stroke_patients s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id
),

-- Get platelet measurements on discharge day
platelet_measurements AS (
  SELECT
    dd.subject_id,
    dd.hadm_id,
    l.charttime,
    l.valuenum AS platelet_count
  FROM
    discharge_dates dd
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON dd.subject_id = l.subject_id AND dd.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    DATE(l.charttime) = dd.discharge_date
    AND d.label = 'Platelet Count'
    AND l.valuenum IS NOT NULL
)

-- Calculate the 75th percentile of platelet counts
SELECT
  PERCENTILE_CONT(platelet_count, 0.75) OVER() AS percentile_75_platelet_count
FROM
  platelet_measurements
LIMIT 1;