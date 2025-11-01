WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 90 AND 100
),

icu_stays_with_age AS (
  SELECT icu.subject_id,
         icu.hadm_id,
         icu.stay_id,
         icu.intime,
         icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN filtered_patients pat ON icu.subject_id = pat.subject_id
),

spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' AND LOWER(label) NOT LIKE '%insp%'
),

first24_spo2 AS (
  SELECT ce.subject_id,
         ce.stay_id,
         ce.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spo2_items s ON ce.itemid = s.itemid
  JOIN icu_stays_with_age icu ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),

aki_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(d.icd_code, r'^584|^N17')
),

spo2_with_aki AS (
  SELECT f.*,
         CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS aki
  FROM first24_spo2 f
  JOIN icu_stays_with_age icu ON f.stay_id = icu.stay_id
  LEFT JOIN aki_diagnoses a ON icu.hadm_id = a.hadm_id
),

spo2_categories AS (
  SELECT *,
         CASE
           WHEN spo2_value < 90 THEN '<90'
           WHEN spo2_value < 93 THEN '90–92'
           WHEN spo2_value < 96 THEN '93–95'
           ELSE '>95'
         END AS spo2_range
  FROM spo2_with_aki
)

SELECT spo2_range,
       COUNT(*) AS n,
       AVG(spo2_value) AS mean_spo2,
       APPROX_QUANTILES(spo2_value, 2)[OFFSET(1)] AS median_spo2,
       APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS q1,
       APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] AS q3,
       APPROX_QUANTILES(spo2_value, 4)[OFFSET(3)] - APPROX_QUANTILES(spo2_value, 4)[OFFSET(1)] AS iqr,
       AVG(CAST(aki AS FLOAT64)) AS aki_rate
FROM spo2_categories
GROUP BY spo2_range
ORDER BY 
  CASE spo2_range
    WHEN '<90' THEN 1
    WHEN '90–92' THEN 2
    WHEN '93–95' THEN 3
    WHEN '>95' THEN 4
  END;