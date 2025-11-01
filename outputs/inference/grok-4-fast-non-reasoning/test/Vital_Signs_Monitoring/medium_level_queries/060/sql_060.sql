WITH first_icu_stays AS (
  SELECT stay_id, subject_id, hadm_id, intime
  FROM (
    SELECT stay_id, subject_id, hadm_id, intime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
eligible_patients AS (
  SELECT f.stay_id, f.subject_id, f.hadm_id, f.intime
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),
max_sbp AS (
  SELECT 
    e.stay_id,
    e.subject_id,
    e.hadm_id,
    MAX(ce.valuenum) AS max_sbp
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON e.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN e.intime AND TIMESTAMP_ADD(e.intime, INTERVAL 24 HOUR)
    AND di.label = 'Arterial systolic blood pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY e.stay_id, e.subject_id, e.hadm_id
  HAVING max_sbp IS NOT NULL  -- Exclude stays with no valid SBP
),
stroke_cohort AS (
  SELECT 
    m.*,
    CASE 
      WHEN m.max_sbp < 130 THEN '<130'
      WHEN m.max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN m.max_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON di.icd_code = dd.icd_code
         AND di.icd_version = dd.icd_version
        WHERE di.subject_id = m.subject_id
          AND di.hadm_id = m.hadm_id
          AND di.icd_version = CAST('10' AS INT64)
          AND di.icd_code LIKE 'I6[0-4]%'  -- I60-I64: specific stroke codes (hemorrhagic/ischemic)
      ) THEN 1 ELSE 0 
    END AS has_stroke
  FROM max_sbp m
),
total_stats AS (
  SELECT 
    COUNT(*) AS total_patients,
    SUM(has_stroke) AS total_strokes
  FROM stroke_cohort
)
SELECT 
  sc.sbp_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / ts.total_patients, 1) AS percent_of_cohort,
  SUM(sc.has_stroke) AS stroke_count,
  ROUND(SUM(sc.has_stroke) * 100.0 / COUNT(*), 1) AS stroke_rate_in_category_pct
FROM stroke_cohort sc
CROSS JOIN total_stats ts
GROUP BY sc.sbp_category, ts.total_patients
ORDER BY 
  CASE sc.sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    ELSE 4
  END
;
-- Overall stroke rate: (total_strokes * 100.0 / total_patients) from total_stats (computed separately if needed);