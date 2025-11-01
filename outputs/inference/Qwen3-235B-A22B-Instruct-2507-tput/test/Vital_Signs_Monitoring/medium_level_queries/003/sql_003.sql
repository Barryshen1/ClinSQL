WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    icu.stay_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime,
    (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON
    p.subject_id = icu.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 71 AND 81
),

temperature_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%temp%'
),

temp_first_48h AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp_48h
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    temperature_items ti
  ON
    ce.itemid = ti.itemid
  INNER JOIN
    patient_age pa
  ON
    ce.stay_id = pa.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= pa.intime
    AND ce.charttime <= DATETIME_ADD(pa.intime, INTERVAL 48 HOUR)
    AND ce.valuenum BETWEEN 30 AND 45
  GROUP BY
    ce.stay_id
  HAVING
    COUNT(ce.valuenum) > 0
),

mi_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    (di.icd_version = 9 AND di.icd_code = '410')
    OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) IN ('I21', 'I22'))
),

stay_with_outcome AS (
  SELECT
    pa.stay_id,
    pa.hadm_id,
    tf.avg_temp_48h,
    CASE
      WHEN tf.avg_temp_48h < 36.0 THEN '<36.0'
      WHEN tf.avg_temp_48h >= 36.0 AND tf.avg_temp_48h < 38.0 THEN '36.0-37.9'
      WHEN tf.avg_temp_48h >= 38.0 THEN '>=38.0'
    END AS temp_category,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM
    patient_age pa
  INNER JOIN
    temp_first_48h tf
  ON
    pa.stay_id = tf.stay_id
  LEFT JOIN
    mi_diagnoses mi
  ON
    pa.hadm_id = mi.hadm_id
)

SELECT
  temp_category,
  ROUND(AVG(avg_temp_48h), 3) AS mean_avg_temp,
  ROUND(APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(50)], 3) AS median_avg_temp,
  ROUND(APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(25)], 3) AS q1_avg_temp,
  ROUND(APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(75)], 3) AS q3_avg_temp,
  ROUND(AVG(has_mi), 3) AS mi_rate
FROM
  stay_with_outcome
WHERE
  temp_category IS NOT NULL
GROUP BY
  temp_category
ORDER BY
  temp_category;