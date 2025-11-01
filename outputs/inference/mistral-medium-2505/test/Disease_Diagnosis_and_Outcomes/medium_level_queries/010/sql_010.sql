WITH
-- Get male patients aged 78-88
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),

-- Get AMI admissions with relevant ICD codes
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- AMI ICD-10 codes (I21.x)
    (d.icd_version = 10 AND di.icd_code LIKE 'I21%')
    -- AMI ICD-9 codes (410.x)
    OR (d.icd_version = 9 AND di.icd_code LIKE '410%')
    -- Exclude shock and respiratory failure
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        -- Shock ICD-10 codes (R57.x)
        (icd_version = 10 AND icd_code LIKE 'R57%')
        -- Shock ICD-9 codes (785.5x)
        OR (icd_version = 9 AND icd_code LIKE '785.5%')
        -- Respiratory failure ICD-10 codes (J96.x)
        OR (icd_version = 10 AND icd_code LIKE 'J96%')
        -- Respiratory failure ICD-9 codes (518.8x)
        OR (icd_version = 9 AND icd_code LIKE '518.8%')
    )
),

-- Calculate comorbidity burden (simplified as count of ICD codes)
comorbidity_burden AS (
  SELECT
    hadm_id,
    subject_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count,
    MAX(CASE WHEN
      -- CKD ICD-10 codes (N18.x)
      (icd_version = 10 AND icd_code LIKE 'N18%')
      -- CKD ICD-9 codes (585.x)
      OR (icd_version = 9 AND icd_code LIKE '585%')
      THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN
      -- Diabetes ICD-10 codes (E11.x, E13.x)
      (icd_version = 10 AND (icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
      -- Diabetes ICD-9 codes (250.x)
      OR (icd_version = 9 AND icd_code LIKE '250%')
      THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id, subject_id
),

-- Combine all data
combined_data AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.los_days,
    a.hospital_expire_flag,
    c.comorbidity_count,
    c.has_ckd,
    c.has_diabetes,
    CASE
      WHEN c.comorbidity_count <= 2 THEN 'low'
      WHEN c.comorbidity_count BETWEEN 3 AND 5 THEN 'med'
      ELSE 'high'
    END AS comorbidity_burden
  FROM
    ami_admissions a
  JOIN
    comorbidity_burden c
    ON a.hadm_id = c.hadm_id
  JOIN
    eligible_patients p
    ON a.subject_id = p.subject_id
),

-- Calculate LOS quartiles
los_quartiles AS (
  SELECT
    hadm_id,
    subject_id,
    los_days,
    hospital_expire_flag,
    comorbidity_count,
    has_ckd,
    has_diabetes,
    comorbidity_burden,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM
    combined_data
)

-- Final analysis
SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  -- Wilson score interval for 95% CI
  ROUND(
    (SUM(hospital_expire_flag) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) -
    1.96 * SQRT(
      (SUM(hospital_expire_flag) * (1 - SUM(hospital_expire_flag)/COUNT(*)) +
      1.96*1.96/4) / (COUNT(*) + 1.96*1.96)
    ) * 100, 2) AS ci_lower,
  ROUND(
    (SUM(hospital_expire_flag) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) +
    1.96 * SQRT(
      (SUM(hospital_expire_flag) * (1 - SUM(hospital_expire_flag)/COUNT(*)) +
      1.96*1.96/4) / (COUNT(*) + 1.96*1.96)
    ) * 100, 2) AS ci_upper,
  ROUND(SUM(has_ckd) * 100.0 / COUNT(*), 2) AS ckd_prevalence,
  ROUND(SUM(has_diabetes) * 100.0 / COUNT(*), 2) AS diabetes_prevalence
FROM
  los_quartiles
GROUP BY
  los_quartile, comorbidity_burden
ORDER BY
  los_quartile, comorbidity_burden;