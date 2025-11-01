WITH
-- Identify female patients aged 86-96 with DM and HF
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND p.subject_id IN (
      -- Patients with DM (ICD-10: E11, E13, E14; ICD-9: 250)
      SELECT DISTINCT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE
        (di.icd_version = 10 AND di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%')
        OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
    )
    AND p.subject_id IN (
      -- Patients with HF (ICD-10: I50; ICD-9: 428)
      SELECT DISTINCT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE
        (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
    )
),

-- Classify medications as Insulin or Oral Agents
medication_classes AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%metformin%' OR
           LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' OR
           LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%saxagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' OR
           LOWER(drug) LIKE '%alogliptin%' OR
           LOWER(drug) LIKE '%canagliflozin%' OR
           LOWER(drug) LIKE '%dapagliflozin%' OR
           LOWER(drug) LIKE '%empagliflozin%' OR
           LOWER(drug) LIKE '%acarbose%' OR
           LOWER(drug) LIKE '%miglitol%' OR
           LOWER(drug) LIKE '%repaglinide%' OR
           LOWER(drug) LIKE '%nateglinide%' THEN 'Oral Agent'
      ELSE 'Other'
    END AS medication_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Identify medications in early period (first 12 hours)
early_medications AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.drug) AS early_med_count
  FROM
    patient_cohort pc
  JOIN
    medication_classes mc
    ON pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON mc.subject_id = p.subject_id AND mc.hadm_id = p.hadm_id AND mc.drug = p.drug
  WHERE
    TIMESTAMP_DIFF(p.starttime, pc.admittime, HOUR) <= 12
  GROUP BY
    pc.subject_id, pc.hadm_id, mc.medication_class
),

-- Identify medications in late period (final 72 hours)
late_medications AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.drug) AS late_med_count
  FROM
    patient_cohort pc
  JOIN
    medication_classes mc
    ON pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON mc.subject_id = p.subject_id AND mc.hadm_id = p.hadm_id AND mc.drug = p.drug
  WHERE
    TIMESTAMP_DIFF(pc.dischtime, p.starttime, HOUR) <= 72
  GROUP BY
    pc.subject_id, pc.hadm_id, mc.medication_class
),

-- Combine early and late medication data
combined_medications AS (
  SELECT
    em.subject_id,
    em.hadm_id,
    em.medication_class AS early_class,
    em.early_med_count,
    lm.medication_class AS late_class,
    lm.late_med_count
  FROM
    early_medications em
  LEFT JOIN
    late_medications lm
    ON em.subject_id = lm.subject_id AND em.hadm_id = lm.hadm_id
),

-- Calculate rates and transitions
final_results AS (
  SELECT
    early_class,
    late_class,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT subject_id) / (SELECT COUNT(DISTINCT subject_id) FROM patient_cohort) * 100 AS percentage,
    COUNT(DISTINCT CASE WHEN early_class = late_class THEN subject_id END) AS same_class_count,
    COUNT(DISTINCT CASE WHEN early_class != late_class THEN subject_id END) AS transition_count
  FROM
    combined_medications
  WHERE
    early_class IN ('Insulin', 'Oral Agent') OR late_class IN ('Insulin', 'Oral Agent')
  GROUP BY
    early_class, late_class
)

-- Final output
SELECT
  early_class,
  late_class,
  patient_count,
  ROUND(percentage, 2) AS percentage,
  same_class_count,
  transition_count
FROM
  final_results
ORDER BY
  early_class, late_class;