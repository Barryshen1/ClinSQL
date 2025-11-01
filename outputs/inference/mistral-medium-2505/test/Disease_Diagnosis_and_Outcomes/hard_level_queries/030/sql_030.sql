WITH
-- Get male inpatients aged 64-74 with upper GI bleeding
base_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
    AND a.admission_type NOT LIKE '%EMERGENCY%'
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code IN (
        'K25.0', 'K25.2', 'K25.4', 'K25.6',
        'K26.0', 'K26.2', 'K26.4', 'K26.6',
        'K28.0', 'K28.2', 'K28.4', 'K28.6',
        'K92.0', 'K92.1', 'K92.2'
      )
    )
),

-- Calculate diagnosis count per admission
diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS diagnosis_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Identify major complications
major_complications AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'N17.%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN icd_code LIKE 'A41.%' OR icd_code LIKE 'R65.2%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN icd_code BETWEEN 'J12' AND 'J18' THEN 1 ELSE 0 END) AS has_pneumonia,
    MAX(CASE WHEN icd_code LIKE 'I63.%' OR icd_code LIKE 'I64' THEN 1 ELSE 0 END) AS has_stroke,
    MAX(CASE WHEN icd_code LIKE 'I21.%' OR icd_code LIKE 'I22.%' THEN 1 ELSE 0 END) AS has_mi
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Calculate composite risk score
risk_scores AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag,
    b.age_at_admission,
    d.diagnosis_count,
    m.has_aki + m.has_sepsis + m.has_pneumonia + m.has_stroke + m.has_mi AS major_complication_count,
    -- Composite score = diagnosis count + 20 × major complication count
    d.diagnosis_count + 20 * (m.has_aki + m.has_sepsis + m.has_pneumonia + m.has_stroke + m.has_mi) AS composite_score
  FROM
    base_patients b
  JOIN
    diagnosis_counts d ON b.hadm_id = d.hadm_id
  JOIN
    major_complications m ON b.hadm_id = m.hadm_id
),

-- Calculate outcomes
outcomes AS (
  SELECT
    r.*,
    -- 30-day mortality
    CASE
      WHEN (r.deathtime IS NOT NULL AND DATETIME_DIFF(r.deathtime, r.admittime, DAY) <= 30)
      OR (r.hospital_expire_flag = 1) THEN 1
      ELSE 0
    END AS died_within_30_days,
    -- Major complication flag
    CASE WHEN r.major_complication_count > 0 THEN 1 ELSE 0 END AS had_major_complication,
    -- Length of stay (for survivors)
    CASE
      WHEN r.deathtime IS NULL OR DATETIME_DIFF(r.deathtime, r.admittime, DAY) > 30
      THEN DATETIME_DIFF(r.dischtime, r.admittime, DAY)
      ELSE NULL
    END AS los_days
  FROM
    risk_scores r
),

-- Create quintiles
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM
    outcomes
)

-- Final aggregation
SELECT
  quintile,
  COUNT(*) AS n,
  ROUND(AVG(composite_score), 2) AS mean_score,
  ROUND(100 * SUM(died_within_30_days) / COUNT(*), 2) AS mortality_30day_percent,
  ROUND(100 * SUM(had_major_complication) / COUNT(*), 2) AS major_complication_percent,
  ROUND(MEDIAN(CASE WHEN died_within_30_days = 0 THEN los_days ELSE NULL END), 2) AS median_los_survivors
FROM
  quintiles
GROUP BY
  quintile
ORDER BY
  quintile;