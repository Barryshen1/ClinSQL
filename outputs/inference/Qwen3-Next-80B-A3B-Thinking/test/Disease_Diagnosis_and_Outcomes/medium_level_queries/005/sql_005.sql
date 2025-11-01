WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
    )
),
icu_status AS (
  SELECT 
    c.*,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
),
los_categories AS (
  SELECT 
    *,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATE_DIFF(dischtime, admittime, DAY) >= 8 THEN '>=8'
      ELSE 'unknown'
    END AS los_category
  FROM icu_status
),
comorbidity_count AS (
  SELECT 
    c.*,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.hadm_id = c.hadm_id
       AND d.seq_num > 1) AS comorbidity_count
  FROM los_categories c
),
charlson_categories AS (
  SELECT 
    *,
    CASE 
      WHEN comorbidity_count <= 3 THEN '<=3'
      WHEN comorbidity_count BETWEEN 4 AND 5 THEN '4-5'
      WHEN comorbidity_count > 5 THEN '>5'
      ELSE 'unknown'
    END AS charlson_category
  FROM comorbidity_count
),
grouped AS (
  SELECT 
    has_icu,
    los_category,
    charlson_category,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    AVG(comorbidity_count) AS mean_comorbidity
  FROM charlson_categories
  GROUP BY has_icu, los_category, charlson_category
)
SELECT 
  has_icu,
  los_category,
  charlson_category,
  (deaths * 100.0 / n) AS mortality_rate,
  ((deaths * 1.0 / n) - 1.96 * SQRT((deaths * 1.0 / n) * (1 - deaths * 1.0 / n) / n)) * 100.0 AS lower_ci,
  ((deaths * 1.0 / n) + 1.96 * SQRT((deaths * 1.0 / n) * (1 - deaths * 1.0 / n) / n)) * 100.0 AS upper_ci,
  mean_comorbidity
FROM grouped
WHERE n > 0
ORDER BY has_icu, los_category, charlson_category;