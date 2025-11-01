WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 38 AND 48
),
systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(label) LIKE '%blood pressure%'
),
icu_sbp_first_48h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_sbp_48h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN systolic_bp_items s ON ce.itemid = s.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON ce.stay_id = i.stay_id
  INNER JOIN patient_ages pa ON i.subject_id = pa.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 50 AND 250
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
percentile_calc AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNTIF(avg_sbp_48h <= 130) AS stays_le_130
  FROM icu_sbp_first_48h
)
SELECT
  SAFE_DIVIDE(ROUND(100.0 * stays_le_130, 2), total_stays) AS percentile
FROM percentile_calc;