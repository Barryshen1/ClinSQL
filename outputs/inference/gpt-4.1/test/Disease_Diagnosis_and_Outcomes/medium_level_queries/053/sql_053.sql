WITH pneumonia_codes AS (
  -- List pneumonia ICD codes for both ICD-9 and ICD-10
  SELECT 'aspiration' AS pneumonia_type, '507' AS icd_code_prefix, 9 AS icd_version
  UNION ALL SELECT 'aspiration', 'J69', 10
  UNION ALL SELECT 'community', '481', 9
  UNION ALL SELECT 'community', '482', 9
  UNION ALL SELECT 'community', '483', 9
  UNION ALL SELECT 'community', '484', 9
  UNION ALL SELECT 'community', '485', 9
  UNION ALL SELECT 'community', '486', 9
  UNION ALL SELECT 'community', 'J13', 10
  UNION ALL SELECT 'community', 'J14', 10
  UNION ALL SELECT 'community', 'J15', 10
  UNION ALL SELECT 'community', 'J16', 10
  UNION ALL SELECT 'community', 'J17', 10
  UNION ALL SELECT 'community', 'J18', 10
),
pneumonia_admissions AS (
  -- Find admissions with aspiration or community-acquired pneumonia
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pn.pneumonia_type
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON adm.hadm_id = dx.hadm_id
  JOIN pneumonia_codes pn
    ON dx.icd_version = pn.icd_version
    AND (
      (pn.icd_version = 9 AND LEFT(dx.icd_code, LENGTH(pn.icd_code_prefix)) = pn.icd_code_prefix)
      OR
      (pn.icd_version = 10 AND LEFT(dx.icd_code, LENGTH(pn.icd_code_prefix)) = pn.icd_code_prefix)
    )
),
male_39_49 AS (
  -- Male patients aged 39–49 at admission
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
cohort AS (
  -- Cohort: male 39–49 with pneumonia
  SELECT
    m.subject_id,
    m.hadm_id,
    m.anchor_age,
    m.gender,
    m.admittime,
    m.dischtime,
    m.hospital_expire_flag,
    pn.pneumonia_type
  FROM male_39_49 m
  JOIN pneumonia_admissions pn
    ON m.subject_id = pn.subject_id AND m.hadm_id = pn.hadm_id
),
los_categorized AS (
  -- Calculate LOS and categorize
  SELECT
    c.*,
    SAFE_CAST(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) >= 8 THEN '8+'
      ELSE NULL
    END AS los_category
  FROM cohort c
),
day1_icu AS (
  -- For each admission, check if patient was in ICU on day 1
  SELECT
    l.hadm_id,
    MAX(
      CASE
        WHEN i.intime < TIMESTAMP_ADD(l.admittime, INTERVAL 1 DAY)
         AND i.outtime > l.admittime
        THEN 1 ELSE 0 END
    ) AS day1_icu
  FROM los_categorized l
  LEFT JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON l.hadm_id = i.hadm_id
  GROUP BY l.hadm_id
),
comorbidity_count AS (
  -- For each admission, count unique non-pneumonia ICD codes
  SELECT
    dx.hadm_id,
    COUNT(DISTINCT dx.icd_code) AS comorbidity_count
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
  LEFT JOIN pneumonia_codes pn
    ON dx.icd_version = pn.icd_version
    AND (
      (pn.icd_version = 9 AND LEFT(dx.icd_code, LENGTH(pn.icd_code_prefix)) = pn.icd_code_prefix)
      OR
      (pn.icd_version = 10 AND LEFT(dx.icd_code, LENGTH(pn.icd_code_prefix)) = pn.icd_code_prefix)
    )
  WHERE pn.icd_code_prefix IS NULL -- exclude pneumonia codes
  GROUP BY dx.hadm_id
),
final AS (
  -- Combine all info
  SELECT
    l.subject_id,
    l.hadm_id,
    l.pneumonia_type,
    l.los_category,
    COALESCE(d.day1_icu, 0) AS day1_icu,
    l.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM los_categorized l
  LEFT JOIN day1_icu d ON l.hadm_id = d.hadm_id
  LEFT JOIN comorbidity_count c ON l.hadm_id = c.hadm_id
  WHERE l.los_category IS NOT NULL
)
-- Aggregate and report
SELECT
  pneumonia_type,
  los_category,
  day1_icu,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
  ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM final
GROUP BY pneumonia_type, los_category, day1_icu
ORDER BY pneumonia_type, los_category, day1_icu
;

-- For absolute/relative mortality differences, you can post-process the above output, e.g.:
-- For each (los_category, day1_icu), compare aspiration vs community-acquired rows:
--   absolute_diff = aspiration_mortality_percent - community_mortality_percent
--   relative_diff = aspiration_mortality_percent / community_mortality_percent;