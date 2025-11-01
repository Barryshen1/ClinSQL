WITH hf_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
         (d.icd_version = 9  AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),
comorbidities AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CONCAT(icd_version, '-', icd_code)) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE NOT (
         (icd_version = 9  AND icd_code LIKE '428%')
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
  )
  GROUP BY hadm_id
),
with_los AS (
  SELECT
    hfp.subject_id,
    hfp.hadm_id,
    hfp.gender,
    hfp.anchor_age,
    DATETIME_DIFF(hfp.dischtime, hfp.admittime, HOUR)/24.0 AS los_days,
    COALESCE(c.comorb_count,0) AS comorb_count,
    hfp.hospital_expire_flag
  FROM hf_patients hfp
  LEFT JOIN comorbidities c
    ON hfp.hadm_id = c.hadm_id
),
with_categories AS (
  SELECT
    *,
    CASE 
      WHEN comorb_count <= 2 THEN 'Low'
      WHEN comorb_count BETWEEN 3 AND 5 THEN 'Medium'
      ELSE 'High'
    END AS comorbidity_category
  FROM with_los
),
with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM with_categories
)
SELECT
  los_quartile,
  comorbidity_category,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percentage
FROM with_quartiles
GROUP BY los_quartile, comorbidity_category
ORDER BY los_quartile, comorbidity_category;