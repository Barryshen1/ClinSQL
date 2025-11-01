WITH eligible_stays AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
),
mean_hr AS (
  SELECT 
    s.stay_id,
    s.hadm_id,
    AVG(c.valuenum) AS mean_hr
  FROM eligible_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON s.stay_id = c.stay_id
  WHERE c.itemid = 220045
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id, s.hadm_id
),
acute_mi AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND icd_code LIKE 'I21%')
)
SELECT 
  CASE 
    WHEN mean_hr < 60 THEN '<60'
    WHEN mean_hr < 100 THEN '60-99'
    WHEN mean_hr < 120 THEN '100-119'
    ELSE '>=120'
  END AS hr_category,
  COUNT(*) AS count_stays,
  COUNT(CASE WHEN m.hadm_id IS NOT NULL THEN 1 END) AS num_with_mi,
  ROUND(100.0 * COUNT(CASE WHEN m.hadm_id IS NOT NULL THEN 1 END) / COUNT(*), 2) AS pct_with_mi
FROM mean_hr h
LEFT JOIN acute_mi m 
  ON h.hadm_id = m.hadm_id
GROUP BY hr_category
ORDER BY 
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;