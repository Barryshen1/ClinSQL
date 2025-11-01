WITH population AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 70 AND 80
),

sbp AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN population p
    ON ce.stay_id = p.stay_id
  WHERE ce.itemid IN (220050, 220179) 
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime <= p.intime + INTERVAL '1' DAY
    AND ce.charttime >= p.intime
  GROUP BY ce.stay_id
),

stroke_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN icd_version = 10 
            AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%') 
          THEN 1 
          ELSE 0 
        END) AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

combined AS (
  SELECT 
    p.stay_id,
    p.hadm_id,
    s.max_sbp,
    COALESCE(sf.has_stroke, 0) AS has_stroke,
    CASE 
      WHEN s.max_sbp < 130 THEN '<130'
      WHEN s.max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN s.max_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN s.max_sbp >= 160 THEN '>=160'
    END AS sbp_category
  FROM population p
  INNER JOIN sbp s
    ON p.stay_id = s.stay_id
  LEFT JOIN stroke_flag sf
    ON p.hadm_id = sf.hadm_id
)

SELECT 
  sbp_category,
  COUNT(*) AS count_in_category,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_total,
  SUM(has_stroke) AS stroke_count,
  ROUND(SUM(has_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate
FROM combined
GROUP BY sbp_category
ORDER BY 
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
  END;