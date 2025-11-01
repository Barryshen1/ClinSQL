WITH
-- Define our patient cohort: male, 40-50 years old, with diabetes and heart failure
patient_cohort AS (
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
    AND p.anchor_age BETWEEN 40 AND 50
    AND p.subject_id IN (
      -- Patients with diabetes (ICD-10 codes E11.x, E13.x)
      SELECT DISTINCT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
    )
    AND p.subject_id IN (
      -- Patients with heart failure (ICD-10 codes I50.x)
      SELECT DISTINCT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'
    )
),

-- Define medication categories
medication_categories AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    drug_type,
    starttime,
    stoptime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%'
        THEN 'Antidiabetic'
      WHEN LOWER(drug) LIKE '%atenolol%' OR LOWER(drug) LIKE '%metoprolol%' OR LOWER(drug) LIKE '%carvedilol%' OR LOWER(drug) LIKE '%bisoprolol%'
        THEN 'Beta-blocker'
      WHEN LOWER(drug) LIKE '%lisinopril%' OR LOWER(drug) LIKE '%enalapril%' OR LOWER(drug) LIKE '%losartan%' OR LOWER(drug) LIKE '%valsartan%' OR LOWER(drug) LIKE '%sacubitril%'
        THEN 'ACEi/ARB/ARNI'
      WHEN LOWER(drug) LIKE '%furosemide%' OR LOWER(drug) LIKE '%bumetanide%' OR LOWER(drug) LIKE '%torsemide%'
        THEN 'Loop diuretic'
      ELSE 'Other'
    END AS medication_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Analyze medication timing relative to admission
medication_timing AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    mc.medication_category,
    mc.starttime,
    mc.stoptime,
    pc.admittime,
    pc.dischtime,
    -- First 24 hours
    TIMESTAMP_DIFF(mc.starttime, pc.admittime, HOUR) AS hours_after_admission,
    -- Last 24 hours
    TIMESTAMP_DIFF(pc.dischtime, mc.stoptime, HOUR) AS hours_before_discharge,
    -- Medication status
    CASE
      WHEN TIMESTAMP_DIFF(mc.starttime, pc.admittime, HOUR) <= 24 AND TIMESTAMP_DIFF(pc.dischtime, mc.stoptime, HOUR) <= 24
        THEN 'Continued'
      WHEN TIMESTAMP_DIFF(mc.starttime, pc.admittime, HOUR) > 24
        THEN 'Initiated late'
      WHEN TIMESTAMP_DIFF(pc.dischtime, mc.stoptime, HOUR) > 24
        THEN 'Discontinued'
      ELSE 'Other'
    END AS medication_status
  FROM
    patient_cohort pc
  JOIN
    medication_categories mc
    ON pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
)

-- Final aggregation
SELECT
  medication_category,
  medication_status,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY medication_category), 2) AS percentage
FROM
  medication_timing
WHERE
  medication_category IN ('Antidiabetic', 'Beta-blocker', 'ACEi/ARB/ARNI', 'Loop diuretic')
GROUP BY
  medication_category, medication_status
ORDER BY
  medication_category, count DESC;