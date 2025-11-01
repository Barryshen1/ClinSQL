WITH cohort AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

sbp_48h AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- SBP itemid
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),

categorized_sbp AS (
  SELECT 
    s.stay_id,
    s.mean_sbp,
    CASE 
      WHEN s.mean_sbp < 140 THEN '<140'
      WHEN s.mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN s.mean_sbp >= 160 THEN '>=160'
    END AS sbp_category
  FROM sbp_48h s
),

mi_diagnoses AS (
  SELECT 
    hadm_id,
    MAX(1) AS has_mi  -- Flag if any MI diagnosis exists
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
    OR (icd_version = 9 AND icd_code LIKE '410%')
  GROUP BY hadm_id
)

SELECT 
  c.sbp_category,
  COUNT(*) AS total_stays,
  COUNT(mi.has_mi) AS mi_stays,
  ROUND(COUNT(mi.has_mi) / COUNT(*) * 100, 2) AS mi_rate_percent,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_sbp), 2) AS category_percent
FROM categorized_sbp c
LEFT JOIN cohort co ON c.stay_id = co.stay_id
LEFT JOIN mi_diagnoses mi ON co.hadm_id = mi.hadm_id
GROUP BY c.sbp_category
ORDER BY c.sbp_category;