WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
),
stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_filtered p ON i.subject_id = p.subject_id
),
sbp AS (
  SELECT 
    s.stay_id, 
    s.subject_id, 
    s.hadm_id, 
    AVG(ce.valuenum) AS mean_sbp
  FROM stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON s.stay_id = ce.stay_id
  WHERE ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= s.intime
    AND ce.charttime <= DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id, s.subject_id, s.hadm_id
  HAVING COUNT(ce.valuenum) > 0
),
mi_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
sbp_with_mi AS (
  SELECT 
    s.*,
    CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM sbp s
  LEFT JOIN mi_hadms m ON s.hadm_id = m.hadm_id
),
summary AS (
  SELECT 
    CASE 
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp < 160 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    COUNT(*) AS num_stays,
    SUM(has_mi) AS num_mi
  FROM sbp_with_mi
  GROUP BY sbp_category
),
total_stays AS (
  SELECT COUNT(*) AS total FROM sbp_with_mi
)
SELECT 
  s.sbp_category,
  ROUND(100.0 * s.num_stays / t.total, 2) AS percent_stays,
  ROUND(100.0 * s.num_mi / s.num_stays, 2) AS mi_rate_percent
FROM summary s
CROSS JOIN total_stays t
ORDER BY 
  CASE s.sbp_category 
    WHEN '<140' THEN 1 
    WHEN '140-159' THEN 2 
    ELSE 3 
  END;