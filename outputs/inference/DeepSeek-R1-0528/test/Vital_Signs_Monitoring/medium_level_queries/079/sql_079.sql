WITH cohort AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 40 AND 50
),
sbp_data AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort 
    ON ce.stay_id = cohort.stay_id
  WHERE 
    ce.itemid IN (220050, 220179)  -- ART SBP & NIBP SBP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= cohort.intime
    AND ce.charttime <= TIMESTAMP_ADD(cohort.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
sbp_categories AS (
  SELECT 
    stay_id,
    mean_sbp,
    CASE 
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp < 160 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category
  FROM sbp_data
),
mi_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '410%') 
    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
combined AS (
  SELECT 
    c.stay_id,
    sc.sbp_category,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mi_flag
  FROM cohort c
  INNER JOIN sbp_categories sc 
    ON c.stay_id = sc.stay_id
  LEFT JOIN mi_admissions mi 
    ON c.hadm_id = mi.hadm_id
),
category_totals AS (
  SELECT 
    sbp_category,
    COUNT(*) AS total_stays,
    SUM(mi_flag) AS mi_stays
  FROM combined
  GROUP BY sbp_category
),
overall AS (
  SELECT COUNT(*) AS total_cohort_stays
  FROM combined
)
SELECT 
  ct.sbp_category,
  ROUND(ct.total_stays * 100.0 / o.total_cohort_stays, 2) AS percent_of_stays,
  ROUND(ct.mi_stays * 100.0 / ct.total_stays, 2) AS mi_rate_percent
FROM category_totals ct, overall o
ORDER BY 
  CASE ct.sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    ELSE 3
  END;