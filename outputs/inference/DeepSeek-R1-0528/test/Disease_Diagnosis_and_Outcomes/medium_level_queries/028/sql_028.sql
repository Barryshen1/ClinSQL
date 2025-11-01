WITH cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag AS mortality,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 43 AND 53
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
    ))
),
comorbidity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    NOT ((icd_version = 9 AND icd_code LIKE '428%')
    OR (icd_version = 10 AND icd_code LIKE 'I50%'))
  GROUP BY hadm_id
),
cohort_with_comorbidity AS (
  SELECT
    c.*,
    COALESCE(com.comorbidity_count, 0) AS comorbidity_count,
    CASE
      WHEN COALESCE(com.comorbidity_count, 0) < 5 THEN 'low'
      WHEN COALESCE(com.comorbidity_count, 0) < 10 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_burden
  FROM cohort c
  LEFT JOIN comorbidity com
    ON c.hadm_id = com.hadm_id
),
cohort_with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort_with_comorbidity
)
SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS total_admissions,
  SUM(mortality) AS deaths,
  ROUND(100 * SUM(mortality) / COUNT(*), 2) AS mortality_rate_pct
FROM cohort_with_quartiles
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;