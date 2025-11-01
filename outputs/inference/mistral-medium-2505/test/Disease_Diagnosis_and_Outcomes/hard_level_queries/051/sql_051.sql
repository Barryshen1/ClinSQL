WITH
-- Get male patients aged 35-45 with acute pancreatitis
base_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        -- Acute pancreatitis ICD codes
        (di.icd_version = 10 AND di.icd_code LIKE 'K85.%') OR
        (di.icd_version = 9 AND di.icd_code = '577.0')
    )
),

-- Count diagnoses per admission
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
    di.hadm_id,
    MAX(CASE WHEN
      (di.icd_version = 10 AND di.icd_code LIKE 'A41.%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'R65.%') OR
      (di.icd_version = 9 AND di.icd_code IN ('995.91', '995.92')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'N17.%') OR
      (di.icd_version = 9 AND di.icd_code LIKE '584.%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'J96.%') OR
      (di.icd_version = 9 AND di.icd_code = '518.81')
    THEN 1 ELSE 0 END) AS has_major_complication,
    SUM(CASE WHEN
      (di.icd_version = 10 AND di.icd_code LIKE 'A41.%') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'R65.%') OR
      (di.icd_version = 9 AND di.icd_code IN ('995.91', '995.92'))
    THEN 1 ELSE 0 END) AS sepsis_flag,
    SUM(CASE WHEN
      (di.icd_version = 10 AND di.icd_code LIKE 'N17.%') OR
      (di.icd_version = 9 AND di.icd_code LIKE '584.%')
    THEN 1 ELSE 0 END) AS aki_flag,
    SUM(CASE WHEN
      (di.icd_version = 10 AND di.icd_code LIKE 'J96.%') OR
      (di.icd_version = 9 AND di.icd_code = '518.81')
    THEN 1 ELSE 0 END) AS respiratory_failure_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY
    di.hadm_id
),

-- Calculate risk score (diagnosis count + 5×major complication flags)
risk_scores AS (
  SELECT
    bp.hadm_id,
    bp.subject_id,
    bp.age_at_admission,
    bp.hospital_expire_flag,
    DATE_DIFF(bp.dischtime, bp.admittime, DAY) AS los_days,
    dc.diagnosis_count,
    mc.has_major_complication,
    mc.sepsis_flag,
    mc.aki_flag,
    mc.respiratory_failure_flag,
    -- Risk score = diagnosis count + 5×(sepsis + AKI + respiratory failure)
    dc.diagnosis_count + 5*(mc.sepsis_flag + mc.aki_flag + mc.respiratory_failure_flag) AS risk_score
  FROM
    base_patients bp
  JOIN
    diagnosis_counts dc ON bp.hadm_id = dc.hadm_id
  JOIN
    major_complications mc ON bp.hadm_id = mc.hadm_id
),

-- Assign quartiles
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    risk_scores
)

-- Final aggregation
SELECT
  CASE
    WHEN risk_quartile IS NULL THEN 'Overall'
    ELSE CONCAT('Quartile ', CAST(risk_quartile AS STRING))
  END AS group_name,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  SUM(has_major_complication) AS major_complications,
  ROUND(SUM(has_major_complication) * 100.0 / COUNT(*), 2) AS major_complication_rate,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)] / 1.0, 2) AS median_los_survivors
FROM
  quartiles
GROUP BY
  ROLLUP(risk_quartile)
ORDER BY
  CASE WHEN group_name = 'Overall' THEN 1 ELSE 0 END,
  risk_quartile;