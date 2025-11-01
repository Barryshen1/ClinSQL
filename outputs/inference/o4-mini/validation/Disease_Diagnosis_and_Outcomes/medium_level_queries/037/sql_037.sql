WITH
-- 1. Base cohort: male patients aged 52-62
base_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- 2. All diagnoses with titles
all_diags AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
),

-- 3. Identify sepsis admissions
sepsis_adm AS (
  SELECT DISTINCT hadm_id
  FROM all_diags
  WHERE LOWER(long_title) LIKE '%sepsis%'
),

-- 4. Determine severity per admission
severity AS (
  SELECT
    ba.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM all_diags d2
        WHERE d2.hadm_id = ba.hadm_id
          AND LOWER(d2.long_title) LIKE '%septic shock%'
      ) THEN 'septic shock'
      ELSE 'no shock'
    END AS sepsis_severity
  FROM base_adm ba
  WHERE ba.hadm_id IN (SELECT hadm_id FROM sepsis_adm)
),

-- 5. Comorbidity count excluding sepsis codes
comorbidity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM all_diags
  WHERE LOWER(long_title) NOT LIKE '%sepsis%'
  GROUP BY hadm_id
),

-- 6. Combine and compute LOS and buckets
final AS (
  SELECT
    s.sepsis_severity,
    CASE
      WHEN DATE_DIFF(s.dischtime, s.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(s.dischtime, s.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '8+'
    END AS los_bucket,
    s.admission_type,
    s.hospital_expire_flag,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM severity s
  LEFT JOIN comorbidity c
    ON s.hadm_id = c.hadm_id
)

-- 7. Aggregate results
SELECT
  sepsis_severity,
  los_bucket,
  admission_type,
  ROUND(100.0 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_pct,
  ROUND(AVG(comorbidity_count), 2)         AS mean_comorbidity_count
FROM final
GROUP BY
  sepsis_severity,
  los_bucket,
  admission_type
ORDER BY
  sepsis_severity,
  los_bucket,
  admission_type;