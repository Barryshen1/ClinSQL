WITH
-- Get female patients aged 67-77 with T2DM and HF
patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND p.subject_id IN (
      -- Patients with T2DM (E11.x)
      SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E11%'
    )
    AND p.subject_id IN (
      -- Patients with HF (I50.x)
      SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'
    )
),

-- Map medications to their classes
medication_classes AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%saxagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' OR
           LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitor'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR
           LOWER(drug) LIKE '%dapagliflozin%' OR
           LOWER(drug) LIKE '%empagliflozin%' OR
           LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitor'
      WHEN LOWER(drug) LIKE '%exenatide%' OR
           LOWER(drug) LIKE '%liraglutide%' OR
           LOWER(drug) LIKE '%dulaglutide%' OR
           LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1 Agonist'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      ELSE 'Other'
    END AS medication_class,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- First 12 hours window
first_12h AS (
  SELECT
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT pc.subject_id) AS patient_count
  FROM
    patient_cohort pc
  JOIN
    medication_classes mc ON pc.hadm_id = mc.hadm_id
  WHERE
    TIMESTAMP_DIFF(mc.starttime, pc.admittime, HOUR) BETWEEN 0 AND 12
  GROUP BY
    pc.hadm_id, mc.medication_class
),

-- Final 48 hours window
final_48h AS (
  SELECT
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT pc.subject_id) AS patient_count
  FROM
    patient_cohort pc
  JOIN
    medication_classes mc ON pc.hadm_id = mc.hadm_id
  WHERE
    TIMESTAMP_DIFF(pc.dischtime, mc.starttime, HOUR) BETWEEN 0 AND 48
    AND TIMESTAMP_DIFF(mc.starttime, pc.admittime, HOUR) >= (pc.admission_duration_hours - 48)
  GROUP BY
    pc.hadm_id, mc.medication_class
),

-- Total patients in cohort
total_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM patient_cohort
)

-- Final results
SELECT
  COALESCE(f12.medication_class, f48.medication_class) AS medication_class,
  SUM(f12.patient_count) AS first_12h_count,
  ROUND(SUM(f12.patient_count) * 100.0 / (SELECT total FROM total_patients), 2) AS first_12h_percent,
  SUM(f48.patient_count) AS final_48h_count,
  ROUND(SUM(f48.patient_count) * 100.0 / (SELECT total FROM total_patients), 2) AS final_48h_percent,
  ROUND((SUM(COALESCE(f48.patient_count, 0)) - SUM(COALESCE(f12.patient_count, 0))) * 100.0 / (SELECT total FROM total_patients), 2) AS net_change_pp
FROM
  (SELECT hadm_id, medication_class, patient_count FROM first_12h) f12
FULL OUTER JOIN
  (SELECT hadm_id, medication_class, patient_count FROM final_48h) f48
ON
  f12.hadm_id = f48.hadm_id AND f12.medication_class = f48.medication_class
GROUP BY
  medication_class
ORDER BY
  net_change_pp DESC;