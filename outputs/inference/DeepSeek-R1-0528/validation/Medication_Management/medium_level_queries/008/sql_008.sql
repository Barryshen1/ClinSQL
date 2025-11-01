WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    TIMESTAMP_ADD(adm.admittime, INTERVAL 24 HOUR) AS first_24h_end,
    TIMESTAMP_SUB(adm.dischtime, INTERVAL 48 HOUR) AS last_48h_start,
    adm.dischtime AS last_48h_end
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 44 AND 54
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        ( -- T2DM: ICD-9 250.x0/x2 OR ICD-10 E11.x
          (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2') AND LENGTH(icd_code) = 5)
          OR (icd_version = 10 AND icd_code LIKE 'E11%')
        )
    )
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        ( -- Heart Failure: ICD-9 428.x OR ICD-10 I50.x, I110, I130, I132
          (icd_version = 9 AND icd_code LIKE '428%')
          OR (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I110', 'I130', 'I132')))
        )
    )
), 
cohort_with_meds AS (
  SELECT 
    c.*,
    p.starttime, 
    p.stoptime, 
    p.drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN 
        LOWER(p.drug) LIKE '%metformin%' OR 
        LOWER(p.drug) LIKE '%glipizide%' OR 
        LOWER(p.drug) LIKE '%glyburide%' OR 
        LOWER(p.drug) LIKE '%glimepiride%' OR 
        LOWER(p.drug) LIKE '%pioglitazone%' OR 
        LOWER(p.drug) LIKE '%rosiglitazone%' OR 
        LOWER(p.drug) LIKE '%sitagliptin%' OR 
        LOWER(p.drug) LIKE '%saxagliptin%' OR 
        LOWER(p.drug) LIKE '%linagliptin%' OR 
        LOWER(p.drug) LIKE '%alogliptin%' OR 
        LOWER(p.drug) LIKE '%repaglinide%' OR 
        LOWER(p.drug) LIKE '%nateglinide%' OR 
        LOWER(p.drug) LIKE '%acarbose%' OR 
        LOWER(p.drug) LIKE '%miglitol%' OR 
        LOWER(p.drug) LIKE '%empagliflozin%' OR 
        LOWER(p.drug) LIKE '%dapagliflozin%' OR 
        LOWER(p.drug) LIKE '%canagliflozin%' THEN 'oral'
      ELSE 'other'
    END AS category
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
),
first_24h AS (
  SELECT 
    hadm_id,
    category,
    MAX(CASE WHEN starttime <= first_24h_end AND stoptime >= admittime THEN 1 ELSE 0 END) AS active,
    COUNT(CASE WHEN starttime BETWEEN admittime AND first_24h_end THEN 1 END) AS initiated_count,
    COUNT(CASE WHEN stoptime BETWEEN admittime AND first_24h_end AND starttime < admittime THEN 1 END) AS discontinued_count,
    COUNT(CASE WHEN starttime < admittime AND stoptime > first_24h_end THEN 1 END) AS continued_count
  FROM cohort_with_meds
  WHERE category IN ('insulin', 'oral')
  GROUP BY hadm_id, category
),
first_24h_full AS (
  SELECT 
    c.hadm_id,
    cat.category,
    COALESCE(f.active, 0) AS active,
    COALESCE(f.initiated_count, 0) AS initiated_count,
    COALESCE(f.discontinued_count, 0) AS discontinued_count,
    COALESCE(f.continued_count, 0) AS continued_count
  FROM (SELECT DISTINCT hadm_id FROM cohort) c
  CROSS JOIN (SELECT 'insulin' AS category UNION ALL SELECT 'oral') cat
  LEFT JOIN first_24h f 
    ON c.hadm_id = f.hadm_id AND cat.category = f.category
),
last_48h AS (
  SELECT 
    hadm_id,
    category,
    MAX(CASE WHEN starttime <= last_48h_end AND stoptime >= last_48h_start THEN 1 ELSE 0 END) AS active,
    COUNT(CASE WHEN starttime BETWEEN last_48h_start AND last_48h_end THEN 1 END) AS initiated_count,
    COUNT(CASE WHEN stoptime BETWEEN last_48h_start AND last_48h_end AND starttime < last_48h_start THEN 1 END) AS discontinued_count,
    COUNT(CASE WHEN starttime < last_48h_start AND stoptime > last_48h_end THEN 1 END) AS continued_count
  FROM cohort_with_meds
  WHERE category IN ('insulin', 'oral')
  GROUP BY hadm_id, category
),
last_48h_full AS (
  SELECT 
    c.hadm_id,
    cat.category,
    COALESCE(l.active, 0) AS active,
    COALESCE(l.initiated_count, 0) AS initiated_count,
    COALESCE(l.discontinued_count, 0) AS discontinued_count,
    COALESCE(l.continued_count, 0) AS continued_count
  FROM (SELECT DISTINCT hadm_id FROM cohort) c
  CROSS JOIN (SELECT 'insulin' AS category UNION ALL SELECT 'oral') cat
  LEFT JOIN last_48h l 
    ON c.hadm_id = l.hadm_id AND cat.category = l.category
),
first_24h_summary AS (
  SELECT 
    'first_24h' AS time_window,
    category,
    COUNT(hadm_id) AS total_admissions,
    SUM(active) AS admissions_with_med,
    ROUND(SUM(active) * 100.0 / COUNT(hadm_id), 2) AS prevalence_percent,
    SUM(initiated_count) AS initiated,
    SUM(discontinued_count) AS discontinued,
    SUM(continued_count) AS continued
  FROM first_24h_full
  GROUP BY category
),
last_48h_summary AS (
  SELECT 
    'last_48h' AS time_window,
    category,
    COUNT(hadm_id) AS total_admissions,
    SUM(active) AS admissions_with_med,
    ROUND(SUM(active) * 100.0 / COUNT(hadm_id), 2) AS prevalence_percent,
    SUM(initiated_count) AS initiated,
    SUM(discontinued_count) AS discontinued,
    SUM(continued_count) AS continued
  FROM last_48h_full
  GROUP BY category
)
SELECT * FROM first_24h_summary
UNION ALL
SELECT * FROM last_48h_summary
ORDER BY time_window, category;