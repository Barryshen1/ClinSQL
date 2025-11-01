WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON ie.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 51 AND 61
),
spo2_avg AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220277  -- SpO2 itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
aki_diagnosis AS (
  SELECT
    hadm_id,
    MAX(CASE
      WHEN (icd_version = 9 AND icd_code LIKE '584%') OR (icd_version = 10 AND icd_code LIKE 'N17%') THEN 1
      ELSE 0
    END) AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
combined_data AS (
  SELECT
    c.stay_id,
    s.avg_spo2,
    COALESCE(a.aki_flag, 0) AS aki_flag,
    CASE
      WHEN s.avg_spo2 < 90 THEN '<90'
      WHEN s.avg_spo2 < 93 THEN '90-92'
      WHEN s.avg_spo2 <= 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM cohort c
  INNER JOIN spo2_avg s
    ON c.stay_id = s.stay_id
  LEFT JOIN aki_diagnosis a
    ON c.hadm_id = a.hadm_id
)
SELECT
  spo2_category,
  COUNT(*) AS total_stays,
  SUM(aki_flag) AS aki_stays,
  ROUND(100.0 * SUM(aki_flag) / COUNT(*), 2) AS aki_rate_percent
FROM combined_data
GROUP BY spo2_category
ORDER BY spo2_category;