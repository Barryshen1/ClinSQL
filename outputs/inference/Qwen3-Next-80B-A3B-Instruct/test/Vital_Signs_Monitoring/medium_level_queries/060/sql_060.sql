WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 70 AND 80
),

sbp_max_24h AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    MAX(c.valuenum) AS max_sbp_24h
  FROM icu_patients i
  JOIN `physionet-data.mimiciv_3_1_icu`.chartevents c
    ON i.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items d
    ON c.itemid = d.itemid
  WHERE d.label IN ('Systolic BP', 'Arterial BP Systolic')
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24 hours'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 300
  GROUP BY i.stay_id, i.hadm_id
),

stroke_diagnosis AS (
  SELECT DISTINCT
    a.hadm_id,
    1 AS has_stroke
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
     OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69')
),

sbp_with_stroke AS (
  SELECT 
    s.stay_id,
    s.max_sbp_24h,
    COALESCE(st.has_stroke, 0) AS has_stroke,
    CASE 
      WHEN s.max_sbp_24h < 130 THEN '<130'
      WHEN s.max_sbp_24h BETWEEN 130 AND 139 THEN '130-139'
      WHEN s.max_sbp_24h BETWEEN 140 AND 159 THEN '140-159'
      WHEN s.max_sbp_24h >= 160 THEN '>=160'
    END AS sbp_category
  FROM sbp_max_24h s
  LEFT JOIN stroke_diagnosis st
    ON s.hadm_id = st.hadm_id
),

total_count AS (
  SELECT COUNT(*) AS total_patients
  FROM sbp_with_stroke
  WHERE sbp_category IS NOT NULL
)

SELECT 
  s.sbp_category,
  ROUND(100.0 * COUNT(*) / t.total_patients, 2) AS percent_of_patients,
  ROUND(100.0 * SUM(s.has_stroke) / COUNT(*), 2) AS stroke_rate_percent
FROM sbp_with_stroke s
CROSS JOIN total_count t
WHERE s.sbp_category IS NOT NULL
GROUP BY s.sbp_category, t.total_patients
ORDER BY 
  CASE s.sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
  END;