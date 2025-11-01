WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    EXTRACT(YEAR FROM ie.intime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
), 
ranked_icustays AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM cohort
  WHERE age_at_admission BETWEEN 70 AND 80
),
filtered_cohort AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM ranked_icustays
  WHERE rn = 1
),
sbp AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_cohort fc 
    ON ce.stay_id = fc.stay_id
  WHERE ce.itemid IN (220179, 220050, 225309)
    AND ce.valuenum BETWEEN 1 AND 300
    AND ce.charttime >= fc.intime
    AND ce.charttime <= DATETIME_ADD(fc.intime, INTERVAL 24 HOUR)
  GROUP BY ce.stay_id
),
stroke_flags AS (
  SELECT 
    hadm_id,
    1 AS stroke_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
    OR 
    (icd_version = 10 AND icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%')
  GROUP BY hadm_id
),
combined AS (
  SELECT 
    fc.stay_id,
    fc.hadm_id,
    s.max_sbp,
    CASE
        WHEN s.max_sbp < 130 THEN '<130'
        WHEN s.max_sbp >= 130 AND s.max_sbp < 140 THEN '130-139'
        WHEN s.max_sbp >= 140 AND s.max_sbp < 160 THEN '140-159'
        WHEN s.max_sbp >= 160 THEN '>=160'
        ELSE NULL
    END AS sbp_category,
    COALESCE(sf.stroke_flag, 0) AS stroke_flag
  FROM filtered_cohort fc
  INNER JOIN sbp s 
    ON fc.stay_id = s.stay_id
  LEFT JOIN stroke_flags sf 
    ON fc.hadm_id = sf.hadm_id
)
SELECT 
  sbp_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM combined), 2) AS percentage,
  ROUND(SUM(stroke_flag) * 100.0 / COUNT(*), 2) AS stroke_rate
FROM combined
GROUP BY sbp_category
ORDER BY 
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
  END;