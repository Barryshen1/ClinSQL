WITH cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 62 AND 72
),

heart_rate_avg AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_heart_rate
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

heart_rate_category AS (
  SELECT
    stay_id,
    CASE
      WHEN mean_heart_rate < 60 THEN '<60'
      WHEN mean_heart_rate BETWEEN 60 AND 99 THEN '60–99'
      WHEN mean_heart_rate BETWEEN 100 AND 119 THEN '100–119'
      WHEN mean_heart_rate >= 120 THEN '≥120'
    END AS hr_category
  FROM
    heart_rate_avg
),

mi_flag AS (
  SELECT DISTINCT
    i.stay_id,
    1 AS has_mi
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    c.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    i.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
)

SELECT
  h.hr_category,
  COUNT(*) AS icu_stay_count,
  ROUND(100 * AVG(COALESCE(m.has_mi, 0)), 2) AS percent_with_mi
FROM
  heart_rate_category h
LEFT JOIN
  mi_flag m
ON
  h.stay_id = m.stay_id
GROUP BY
  h.hr_category
ORDER BY
  CASE h.hr_category
    WHEN '<60' THEN 1
    WHEN '60–99' THEN 2
    WHEN '100–119' THEN 3
    WHEN '≥120' THEN 4
  END;