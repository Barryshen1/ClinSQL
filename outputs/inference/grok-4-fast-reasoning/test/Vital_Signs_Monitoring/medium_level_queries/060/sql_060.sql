WITH patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 70 AND 80
),
first_stays AS (
  SELECT subject_id, stay_id, hadm_id, intime
  FROM (
    SELECT subject_id, stay_id, hadm_id, intime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.subject_id IN (SELECT subject_id FROM patients)
  )
  WHERE rn = 1
),
sbp_max AS (
  SELECT fs.subject_id, fs.stay_id, fs.hadm_id,
         MAX(ce.valuenum) AS max_sbp
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= fs.intime
    AND ce.charttime < TIMESTAMP_ADD(fs.intime, INTERVAL 1 DAY)
    AND di.label = 'Systolic blood pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY fs.subject_id, fs.stay_id, fs.hadm_id
),
strokes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE (icd_version = 10 AND icd_code LIKE 'I6[1-4]%')
     OR (icd_version = 9 AND icd_code IN ('430', '431', '432', '433', '434', '436'))
),
categorized AS (
  SELECT sm.*,
         CASE
           WHEN max_sbp < 130 THEN '<130'
           WHEN max_sbp >= 130 AND max_sbp <= 139 THEN '130–139'
           WHEN max_sbp >= 140 AND max_sbp <= 159 THEN '140–159'
           ELSE '≥160'
         END AS sbp_category,
         CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_stroke
  FROM sbp_max sm
  LEFT JOIN strokes s
    ON sm.hadm_id = s.hadm_id
)
SELECT
  sbp_category,
  COUNT(*) AS num_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent,
  SUM(has_stroke) AS stroke_count,
  ROUND(AVG(has_stroke) * 100.0, 2) AS stroke_rate_percent
FROM categorized
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130–139' THEN 2
    WHEN '140–159' THEN 3
    WHEN '≥160' THEN 4
  END;