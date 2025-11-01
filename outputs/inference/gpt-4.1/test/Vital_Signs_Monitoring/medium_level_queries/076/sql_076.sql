WITH hr_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
creat_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),
female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    EXTRACT(YEAR FROM icu.intime) AS icu_year,
    -- Calculate age at ICU stay
    (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 48 AND 58
),
hr_first48 AS (
  SELECT
    s.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM female_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.subject_id = c.subject_id
    AND s.hadm_id = c.hadm_id
    AND s.stay_id = c.stay_id
  JOIN hr_itemid hri
    ON c.itemid = hri.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
),
creat_first48 AS (
  SELECT
    s.stay_id,
    MIN(l.valuenum) AS min_creat48,
    MAX(l.valuenum) AS max_creat48
  FROM female_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
  JOIN creat_itemid ci
    ON l.itemid = ci.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
),
creat_baseline AS (
  -- Baseline: lowest creatinine in 7 days before ICU admission
  SELECT
    s.stay_id,
    MIN(l.valuenum) AS baseline_creat
  FROM female_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.subject_id = l.subject_id
    AND s.hadm_id = l.hadm_id
  JOIN creat_itemid ci
    ON l.itemid = ci.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.charttime BETWEEN TIMESTAMP_SUB(s.intime, INTERVAL 7 DAY) AND s.intime
  GROUP BY s.stay_id
),
aki_per_stay AS (
  SELECT
    hr.stay_id,
    hr.avg_hr,
    -- HR category
    CASE
      WHEN hr.avg_hr < 60 THEN '<60'
      WHEN hr.avg_hr >= 60 AND hr.avg_hr < 100 THEN '60-99'
      WHEN hr.avg_hr >= 100 AND hr.avg_hr < 120 THEN '100-119'
      WHEN hr.avg_hr >= 120 THEN '>=120'
      ELSE 'Unknown'
    END AS hr_category,
    cf.min_creat48,
    cf.max_creat48,
    cb.baseline_creat,
    -- AKI determination (KDIGO, simplified)
    CASE
      WHEN cb.baseline_creat IS NULL OR cf.max_creat48 IS NULL THEN 'Unknown'
      WHEN cf.max_creat48 - cb.baseline_creat >= 0.3 THEN 'AKI'
      WHEN cf.max_creat48 / cb.baseline_creat >= 1.5 THEN 'AKI'
      ELSE 'No AKI'
    END AS aki_flag
  FROM hr_first48 hr
  LEFT JOIN creat_first48 cf
    ON hr.stay_id = cf.stay_id
  LEFT JOIN creat_baseline cb
    ON hr.stay_id = cb.stay_id
)
SELECT
  hr_category,
  COUNT(*) AS n_stays,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_stays,
  SUM(CASE WHEN aki_flag = 'AKI' THEN 1 ELSE 0 END) AS n_aki,
  ROUND(SUM(CASE WHEN aki_flag = 'AKI' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS aki_rate_percent
FROM aki_per_stay
WHERE hr_category != 'Unknown'
GROUP BY hr_category
ORDER BY
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;