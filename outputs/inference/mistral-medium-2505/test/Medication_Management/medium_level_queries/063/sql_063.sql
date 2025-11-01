WITH
-- Get male patients aged 45-55 with diabetes and heart failure
patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS total_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hadm_id IN (
      -- Patients with diabetes (E11.x, E13.x)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'
    )
    AND a.hadm_id IN (
      -- Patients with heart failure (I50.x)
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I50%'
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 12 -- At least 12h stay
),

-- Identify insulin prescriptions
insulin_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%'
      OR formulary_drug_cd IN (
        -- Common insulin formulary codes (example - may need adjustment)
        SELECT formulary_drug_cd
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
        WHERE LOWER(drug) LIKE '%insulin%'
        LIMIT 100
      )
      THEN TRUE
      ELSE FALSE
    END AS is_insulin
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Identify oral antidiabetic prescriptions
oral_antidiabetic_prescriptions AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%'
      OR LOWER(drug) LIKE '%glipizide%'
      OR LOWER(drug) LIKE '%glyburide%'
      OR LOWER(drug) LIKE '%glimepiride%'
      OR formulary_drug_cd IN (
        -- Common oral antidiabetic formulary codes (example - may need adjustment)
        SELECT formulary_drug_cd
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
        WHERE LOWER(drug) LIKE '%metformin%'
          OR LOWER(drug) LIKE '%glipizide%'
          OR LOWER(drug) LIKE '%glyburide%'
          OR LOWER(drug) LIKE '%glimepiride%'
        LIMIT 100
      )
      THEN TRUE
      ELSE FALSE
    END AS is_oral_antidiabetic
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- First 12 hours window
first_12h AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    MAX(CASE WHEN ip.is_insulin THEN 1 ELSE 0 END) AS has_insulin,
    MAX(CASE WHEN oap.is_oral_antidiabetic THEN 1 ELSE 0 END) AS has_oral_antidiabetic
  FROM
    patient_cohort pc
  LEFT JOIN
    insulin_prescriptions ip
    ON pc.subject_id = ip.subject_id
    AND pc.hadm_id = ip.hadm_id
    AND ip.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 12 HOUR)
  LEFT JOIN
    oral_antidiabetic_prescriptions oap
    ON pc.subject_id = oap.subject_id
    AND pc.hadm_id = oap.hadm_id
    AND oap.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 12 HOUR)
  GROUP BY
    pc.subject_id, pc.hadm_id
),

-- Final 72 hours window
final_72h AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    MAX(CASE WHEN ip.is_insulin THEN 1 ELSE 0 END) AS has_insulin,
    MAX(CASE WHEN oap.is_oral_antidiabetic THEN 1 ELSE 0 END) AS has_oral_antidiabetic
  FROM
    patient_cohort pc
  LEFT JOIN
    insulin_prescriptions ip
    ON pc.subject_id = ip.subject_id
    AND pc.hadm_id = ip.hadm_id
    AND ip.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 72 HOUR) AND pc.dischtime
  LEFT JOIN
    oral_antidiabetic_prescriptions oap
    ON pc.subject_id = oap.subject_id
    AND pc.hadm_id = oap.hadm_id
    AND oap.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 72 HOUR) AND pc.dischtime
  GROUP BY
    pc.subject_id, pc.hadm_id
),

-- Combine results
combined_results AS (
  SELECT
    COUNT(DISTINCT pc.subject_id) AS total_patients,
    SUM(f12h.has_insulin) AS first_12h_insulin,
    SUM(f12h.has_oral_antidiabetic) AS first_12h_oral,
    SUM(f72h.has_insulin) AS final_72h_insulin,
    SUM(f72h.has_oral_antidiabetic) AS final_72h_oral
  FROM
    patient_cohort pc
  LEFT JOIN
    first_12h f12h ON pc.subject_id = f12h.subject_id AND pc.hadm_id = f12h.hadm_id
  LEFT JOIN
    final_72h f72h ON pc.subject_id = f72h.subject_id AND pc.hadm_id = f72h.hadm_id
)

-- Final calculation
SELECT
  total_patients,
  ROUND(100 * first_12h_insulin / total_patients, 2) AS first_12h_insulin_pct,
  ROUND(100 * first_12h_oral / total_patients, 2) AS first_12h_oral_pct,
  ROUND(100 * final_72h_insulin / total_patients, 2) AS final_72h_insulin_pct,
  ROUND(100 * final_72h_oral / total_patients, 2) AS final_72h_oral_pct,
  ROUND(100 * (first_12h_insulin - final_72h_insulin) / total_patients, 2) AS insulin_pp_diff,
  ROUND(100 * (first_12h_oral - final_72h_oral) / total_patients, 2) AS oral_pp_diff
FROM
  combined_results;