WITH diag AS (
  SELECT
    d.hadm_id,
    d.icd_code,
    LOWER(cd.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` cd
      ON d.icd_code = cd.icd_code
      AND d.icd_version = cd.icd_version
),

sepsis_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN long_title LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_shock,
    MAX(CASE WHEN long_title LIKE '%sepsis%' THEN 1 ELSE 0 END) AS has_sepsis
  FROM diag
  GROUP BY hadm_id
),

comorb_count AS (
  -- count distinct diagnosis codes per admission excluding sepsis-related diagnoses
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorb_count
  FROM diag
  WHERE NOT (long_title LIKE '%sepsis%')
  GROUP BY hadm_id
)

SELECT
  severity,
  los_category,
  admission_type,
  COUNT(*) AS n_admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hosp_mortality_pct,
  ROUND(AVG(COALESCE(comorb_count, 0)), 2) AS mean_comorbidity_count
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admission_type,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 >= 8 THEN '>=8'
      ELSE '0 or <1'
    END AS los_category,
    a.hospital_expire_flag,
    CASE WHEN s.has_shock = 1 THEN 'septic_shock' ELSE 'no_shock' END AS severity,
    COALESCE(c.comorb_count, 0) AS comorb_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
    JOIN sepsis_flags s
      ON a.hadm_id = s.hadm_id
    LEFT JOIN comorb_count c
      ON a.hadm_id = c.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND s.has_sepsis = 1
) t
GROUP BY
  severity,
  los_category,
  admission_type
ORDER BY
  severity,
  admission_type,
  CASE los_category WHEN '1-3' THEN 1 WHEN '4-7' THEN 2 WHEN '>=8' THEN 3 ELSE 0 END;