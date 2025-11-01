WITH icu_patients AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 70 AND 80
),

systolic_bp AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(linksto) = 'chartevents'
),

bp_first_24h AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS max_sbp_24h
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN systolic_bp sbp ON ce.itemid = sbp.itemid
  JOIN icu_patients ip ON ce.stay_id = ip.stay_id
  WHERE ce.charttime >= ip.intime
    AND ce.charttime < DATETIME_ADD(ip.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- reasonable SBP range
  GROUP BY ce.stay_id
),

stroke_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (di.icd_version = 10 AND di.icd_code LIKE 'I63%'
         OR di.icd_code LIKE 'I64%'
         OR di.icd_code LIKE 'G45%')
),

icu_with_sbp_and_stroke AS (
  SELECT 
    ip.stay_id,
    ip.hadm_id,
    bp.max_sbp_24h,
    CASE 
      WHEN bp.max_sbp_24h < 130 THEN '<130'
      WHEN bp.max_sbp_24h BETWEEN 130 AND 139 THEN '130-139'
      WHEN bp.max_sbp_24h BETWEEN 140 AND 159 THEN '140-159'
      WHEN bp.max_sbp_24h >= 160 THEN '>=160'
      ELSE NULL 
    END AS sbp_category,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_stroke
  FROM icu_patients ip
  JOIN bp_first_24h bp ON ip.stay_id = bp.stay_id
  LEFT JOIN stroke_diagnoses s ON ip.hadm_id = s.hadm_id
  WHERE bp.max_sbp_24h IS NOT NULL
),

summary AS (
  SELECT
    sbp_category,
    COUNT(*) AS patient_count,
    SUM(had_stroke) AS stroke_count
  FROM icu_with_sbp_and_stroke
  WHERE sbp_category IS NOT NULL
  GROUP BY sbp_category
),

totals AS (
  SELECT SUM(patient_count) AS total_patients
  FROM summary
)

SELECT
  s.sbp_category,
  ROUND(100.0 * s.patient_count / t.total_patients, 2) AS percent_patients,
  ROUND(100.0 * s.stroke_count / s.patient_count, 2) AS stroke_rate_percent
FROM summary s
CROSS JOIN totals t
ORDER BY
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
  END;