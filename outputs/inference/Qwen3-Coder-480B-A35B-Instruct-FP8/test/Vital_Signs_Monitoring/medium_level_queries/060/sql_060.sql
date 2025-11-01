WITH sbp_first24h AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    LOWER(di.label) LIKE '%systolic%'
    AND di.category = 'Blood Pressure'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
  GROUP BY
    icu.subject_id, icu.hadm_id, icu.stay_id
),
sbp_categories AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    max_sbp,
    CASE
      WHEN max_sbp < 130 THEN '<130'
      WHEN max_sbp < 140 THEN '130–139'
      WHEN max_sbp < 160 THEN '140–159'
      ELSE '≥160'
    END AS sbp_category
  FROM sbp_first24h
),
stroke_flag AS (
  SELECT
    hadm_id,
    CASE
      WHEN LOWER(diag.long_title) LIKE '%stroke%' THEN 1
      ELSE 0
    END AS is_stroke
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_icd
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON diag_icd.icd_code = diag.icd_code
    AND diag_icd.icd_version = diag.icd_version
)
SELECT
  sbp_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_patients,
  SUM(stroke.is_stroke) AS stroke_count,
  ROUND(SUM(stroke.is_stroke) * 100.0 / COUNT(*), 2) AS stroke_rate
FROM
  sbp_categories
LEFT JOIN
  stroke_flag AS stroke
  ON sbp_categories.hadm_id = stroke.hadm_id
GROUP BY
  sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130–139' THEN 2
    WHEN '140–159' THEN 3
    WHEN '≥160' THEN 4
  END;