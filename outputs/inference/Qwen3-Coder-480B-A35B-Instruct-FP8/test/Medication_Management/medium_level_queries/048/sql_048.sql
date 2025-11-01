WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS hosp_los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'F'
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),

-- Identify patients with both diabetes and heart failure
diabetes_hf AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    SUM(CASE WHEN LOWER(did.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS diabetes_count,
    SUM(CASE WHEN LOWER(did.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS hf_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
  ON
    d.icd_code = did.icd_code
    AND d.icd_version = did.icd_version
  WHERE
    LOWER(did.long_title) LIKE '%diabetes%'
    OR LOWER(did.long_title) LIKE '%heart failure%'
  GROUP BY
    c.subject_id, c.hadm_id
  HAVING
    diabetes_count > 0 AND hf_count > 0
),

-- Filter cohort to only those with both conditions
filtered_cohort AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    diabetes_hf dh
  ON
    c.hadm_id = dh.hadm_id
),

-- Identify insulin administrations
insulin_admins AS (
  SELECT
    ph.hadm_id,
    ph.medication,
    ph.sliding_scale,
    ph.starttime AS charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  WHERE
    LOWER(ph.medication) LIKE '%insulin%'
),

-- Classify insulin types
insulin_classified AS (
  SELECT
    ia.hadm_id,
    ia.charttime,
    CASE
      WHEN LOWER(ia.medication) LIKE '%glargine%' OR LOWER(ia.medication) LIKE '%detemir%' OR LOWER(ia.medication) LIKE '%degludec%' THEN 'Basal'
      WHEN LOWER(ia.medication) LIKE '%aspart%' OR LOWER(ia.medication) LIKE '%lispro%' OR LOWER(ia.medication) LIKE '%glulisine%' OR LOWER(ia.medication) LIKE '%regular%' THEN 'Bolus'
      WHEN ia.sliding_scale = '1' OR LOWER(ia.medication) LIKE '%sliding%' THEN 'Sliding Scale'
      ELSE 'Other'
    END AS insulin_type
  FROM
    insulin_admins ia
),

-- Add time windows
insulin_timewindow AS (
  SELECT
    ic.hadm_id,
    ic.insulin_type,
    CASE
      WHEN ic.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) THEN 'first_48h'
      WHEN ic.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 'final_48h'
      ELSE 'other'
    END AS time_window
  FROM
    insulin_classified ic
  JOIN
    filtered_cohort c
  ON
    ic.hadm_id = c.hadm_id
  WHERE
    ic.insulin_type IN ('Basal', 'Bolus', 'Sliding Scale')
),

-- Aggregate by patient and time window
patient_insulin_summary AS (
  SELECT
    hadm_id,
    time_window,
    STRING_AGG(DISTINCT insulin_type ORDER BY insulin_type) AS insulin_types
  FROM
    insulin_timewindow
  GROUP BY
    hadm_id, time_window
),

-- Pivot to get first and final insulin types
pivot_insulin AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN time_window = 'first_48h' THEN insulin_types END) AS first_48h_types,
    MAX(CASE WHEN time_window = 'final_48h' THEN insulin_types END) AS final_48h_types
  FROM
    patient_insulin_summary
  GROUP BY
    hadm_id
),

-- Final classification
final_classification AS (
  SELECT
    hadm_id,
    first_48h_types,
    final_48h_types,
    CASE
      WHEN first_48h_types LIKE '%Basal%' AND first_48h_types NOT LIKE '%Bolus%' THEN 'Basal'
      WHEN first_48h_types LIKE '%Bolus%' AND first_48h_types NOT LIKE '%Basal%' THEN 'Bolus'
      WHEN first_48h_types LIKE '%Basal%' AND first_48h_types LIKE '%Bolus%' THEN 'Basal-Bolus'
      WHEN first_48h_types LIKE '%Sliding Scale%' THEN 'Sliding Scale'
      ELSE 'Other'
    END AS first_insulin_category,
    CASE
      WHEN final_48h_types LIKE '%Basal%' AND final_48h_types NOT LIKE '%Bolus%' THEN 'Basal'
      WHEN final_48h_types LIKE '%Bolus%' AND final_48h_types NOT LIKE '%Basal%' THEN 'Bolus'
      WHEN final_48h_types LIKE '%Basal%' AND final_48h_types LIKE '%Bolus%' THEN 'Basal-Bolus'
      WHEN final_48h_types LIKE '%Sliding Scale%' THEN 'Sliding Scale'
      ELSE 'Other'
    END AS final_insulin_category
  FROM
    pivot_insulin
),

-- Count total patients
total_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM final_classification
),

-- First 48h insulin type percentages
first_48h_summary AS (
  SELECT
    first_insulin_category AS insulin_type,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / tp.total, 2) AS percentage
  FROM
    final_classification
  CROSS JOIN
    total_patients tp
  GROUP BY
    first_insulin_category, tp.total
),

-- Final 48h insulin type percentages
final_48h_summary AS (
  SELECT
    final_insulin_category AS insulin_type,
    COUNT(DISTINCT hadm_id) AS patient_count,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / tp.total, 2) AS percentage
  FROM
    final_classification
  CROSS JOIN
    total_patients tp
  GROUP BY
    final_insulin_category, tp.total
),

-- Transition matrix
transitions AS (
  SELECT
    first_insulin_category,
    final_insulin_category,
    COUNT(DISTINCT hadm_id) AS patient_count
  FROM
    final_classification
  GROUP BY
    first_insulin_category,
    final_insulin_category
)

-- Final output
SELECT
  'First 48h' AS period,
  insulin_type,
  patient_count,
  percentage
FROM
  first_48h_summary

UNION ALL

SELECT
  'Final 48h' AS period,
  insulin_type,
  patient_count,
  percentage
FROM
  final_48h_summary

ORDER BY
  period,
  insulin_type;