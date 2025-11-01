WITH base AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    a.discharge_location,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_version = 10
      AND d.icd_code LIKE 'I21%'
  )
  AND a.hadm_id NOT IN (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_version = 10
      AND (d.icd_code LIKE 'R57%' OR d.icd_code LIKE 'J96%')
  )
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 69 AND 79
),
mortality_median AS (
  SELECT
    los_category,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_percent,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los
  FROM base
  WHERE los_category IS NOT NULL
  GROUP BY los_category
),
discharge_destinations AS (
  SELECT
    los_category,
    discharge_location,
    COUNT(*) AS count
  FROM base
  WHERE los_category IS NOT NULL
  GROUP BY los_category, discharge_location
)
SELECT
  mm.los_category,
  mm.mortality_percent,
  mm.median_los,
  STRING_AGG(CONCAT(dd.discharge_location, ': ', CAST(dd.count AS STRING)), ', ') AS discharge_destinations
FROM mortality_median mm
JOIN discharge_destinations dd ON mm.los_category = dd.los_category
GROUP BY mm.los_category, mm.mortality_percent, mm.median_los;