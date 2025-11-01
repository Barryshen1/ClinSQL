WITH
-- Get patient demographics and admission details
patient_admissions AS (
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
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    -- Calculate length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 69 AND 79
),

-- Identify GI bleed diagnoses
gi_bleeds AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code IN ('K250', 'K251', 'K252', 'K253', 'K254', 'K255', 'K256', 'K257', 'K259',
                          'K260', 'K261', 'K262', 'K263', 'K264', 'K265', 'K266', 'K269',
                          'K270', 'K271', 'K272', 'K273', 'K274', 'K275', 'K276', 'K279',
                          'K280', 'K281', 'K282', 'K283', 'K284', 'K285', 'K286', 'K289',
                          'K920', 'K921') THEN 'Upper GI bleed'
      WHEN d.icd_code IN ('K552', 'K573', 'K625', 'K922') THEN 'Lower GI bleed'
      ELSE NULL
    END AS bleed_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_version = 10
),

-- Identify ICU stays and day-1 ICU status
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    -- Check if patient was in ICU on day 1 of admission
    CASE WHEN DATE(i.intime) = DATE(a.admittime) THEN 1 ELSE 0 END AS day1_icu,
    -- Check if patient had any ICU stay
    1 AS any_icu_stay
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    patient_admissions a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Combine all data
combined_data AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.age,
    pa.los_days,
    pa.hospital_expire_flag,
    gb.bleed_type,
    COALESCE(ic.day1_icu, 0) AS day1_icu,
    MAX(COALESCE(ic.any_icu_stay, 0)) AS any_icu_stay
  FROM
    patient_admissions pa
  JOIN
    gi_bleeds gb ON pa.subject_id = gb.subject_id AND pa.hadm_id = gb.hadm_id
  LEFT JOIN
    icu_stays ic ON pa.subject_id = ic.subject_id AND pa.hadm_id = ic.hadm_id
  WHERE
    gb.bleed_type IS NOT NULL
  GROUP BY
    pa.subject_id, pa.hadm_id, pa.age, pa.los_days, pa.hospital_expire_flag, gb.bleed_type, ic.day1_icu
),

-- Categorize LOS
los_categories AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 2 THEN '1-2 days'
      WHEN los_days BETWEEN 3 AND 5 THEN '3-5 days'
      WHEN los_days BETWEEN 6 AND 9 THEN '6-9 days'
      WHEN los_days >= 10 THEN '10+ days'
      ELSE 'Other'
    END AS los_category
  FROM
    combined_data
)

-- Final aggregation
SELECT
  bleed_type,
  los_category,
  day1_icu,
  COUNT(*) AS patient_count,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_rate,
  SUM(any_icu_stay) AS icu_admissions,
  ROUND(100 * SUM(any_icu_stay) / COUNT(*), 1) AS icu_admission_rate
FROM
  los_categories
GROUP BY
  bleed_type, los_category, day1_icu
ORDER BY
  bleed_type, los_category, day1_icu;