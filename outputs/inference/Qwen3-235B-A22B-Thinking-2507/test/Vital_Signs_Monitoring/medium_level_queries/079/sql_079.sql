WITH population AS (
  SELECT 
    icu.subject_id, 
    icu.hadm_id, 
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) BETWEEN 40 AND 50
),

sbp_data AS (
  SELECT 
    p.stay_id,
    ce.valuenum AS sbp
  FROM population p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON p.stay_id = ce.stay_id
  WHERE ce.itemid IN (220050, 224167)
    AND ce.charttime >= p.intime
    AND ce.charttime <= p.intime + INTERVAL '48' HOUR
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),

sbp_mean AS (
  SELECT 
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM sbp_data
  GROUP BY stay_id
),

sbp_categories AS (
  SELECT 
    stay_id,
    mean_sbp,
    CASE 
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN mean_sbp >= 160 THEN '>=160'
    END AS sbp_category
  FROM sbp_mean
),

mi_status AS (
  SELECT 
    p.stay_id,
    MAX(CASE 
          WHEN (d.icd_version = 10 AND (d.icd_code LIKE 'I21.%' OR d.icd_code LIKE 'I22.%'))
            OR (d.icd_version = 9 AND d.icd_code LIKE '410.%')
          THEN 1 
          ELSE 0 
        END) AS has_mi
  FROM population p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.hadm_id = d.hadm_id
  GROUP BY p.stay_id
),

combined AS (
  SELECT 
    sc.stay_id,
    sc.sbp_category,
    mi.has_mi
  FROM sbp_categories sc
  LEFT JOIN mi_status mi
    ON sc.stay_id = mi.stay_id
),

totals AS (
  SELECT 
    sbp_category,
    COUNT(*) AS n_stays,
    SUM(has_mi) AS n_mi
  FROM combined
  GROUP BY sbp_category
),

total_stays AS (
  SELECT COUNT(*) AS total FROM sbp_categories
),

categories AS (
  SELECT '<140' AS sbp_category
  UNION ALL
  SELECT '140-159'
  UNION ALL
  SELECT '>=160'
)

SELECT 
  c.sbp_category,
  COALESCE(t.n_stays, 0) AS n_stays,
  ROUND(COALESCE(t.n_stays * 100.0 / ts.total, 0), 2) AS percent_in_category,
  ROUND(CASE 
          WHEN COALESCE(t.n_stays, 0) > 0 THEN COALESCE(t.n_mi * 100.0 / t.n_stays, 0)
          ELSE 0
        END, 2) AS mi_rate_percent
FROM categories c
LEFT JOIN totals t ON c.sbp_category = t.sbp_category
CROSS JOIN total_stays ts
ORDER BY 
  CASE c.sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;