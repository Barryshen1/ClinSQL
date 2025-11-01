WITH
-- Get female patients aged 48-58
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 48 AND 58
),

-- Get stroke admissions
stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.subject_id IN (SELECT subject_id FROM female_patients)
    AND (d.icd_code LIKE 'I6%' OR d.icd_code LIKE '43%') -- Stroke ICD-10 and ICD-9 codes
    AND di.long_title LIKE '%cerebrovascular%'
),

-- Identify ICU stays
icu_stays AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_icu.transfers`
  WHERE
    careunit IN ('MICU', 'SICU', 'CSICU', 'TSICU', 'CCU', 'NICU')
),

-- Calculate comorbidity burden (count of distinct non-stroke diagnoses)
comorbidity_counts AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.subject_id, d.hadm_id) IN (SELECT subject_id, hadm_id FROM stroke_admissions)
    AND NOT (d.icd_code LIKE 'I6%' OR d.icd_code LIKE '43%') -- Exclude stroke codes
  GROUP BY
    subject_id, hadm_id
),

-- Categorize comorbidity burden
comorbidity_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN comorbidity_count <= 2 THEN 'Low'
      WHEN comorbidity_count BETWEEN 3 AND 5 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_burden
  FROM
    comorbidity_counts
),

-- Combine all data
combined_data AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.los_days,
    sa.hospital_expire_flag,
    CASE WHEN icu.subject_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status,
    CASE WHEN sa.los_days <= 5 THEN '≤5 days' ELSE '>5 days' END AS los_category,
    COALESCE(cc.comorbidity_burden, 'Low') AS comorbidity_burden
  FROM
    stroke_admissions sa
  LEFT JOIN
    icu_stays icu
    ON sa.subject_id = icu.subject_id AND sa.hadm_id = icu.hadm_id
  LEFT JOIN
    comorbidity_categories cc
    ON sa.subject_id = cc.subject_id AND sa.hadm_id = cc.hadm_id
)

-- Final aggregation with mortality rates and 95% CIs
SELECT
  icu_status,
  los_category,
  comorbidity_burden,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_rate,
  -- Calculate 95% CI using Wilson score interval
  ROUND(100 * (
    (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) -
    1.96 * SQRT(
      (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * (COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)) +
      1.96*1.96/4) /
      (COUNT(*) + 1.96*1.96)
    )
  ) / (COUNT(*) + 1.96*1.96) * 100, 2) AS ci_lower,
  ROUND(100 * (
    (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) + 1.96*1.96/2) /
    (COUNT(*) + 1.96*1.96) +
    1.96 * SQRT(
      (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * (COUNT(*) - SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)) +
      1.96*1.96/4) /
      (COUNT(*) + 1.96*1.96)
    )
  ) / (COUNT(*) + 1.96*1.96) * 100, 2) AS ci_upper
FROM
  combined_data
GROUP BY
  icu_status, los_category, comorbidity_burden
ORDER BY
  icu_status, los_category, comorbidity_burden;