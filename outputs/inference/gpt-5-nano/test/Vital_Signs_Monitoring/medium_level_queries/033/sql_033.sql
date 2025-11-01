WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 62 AND 72
),
hr_per_stay AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
   AND ce.charttime BETWEEN c.intime AND c.outtime
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
mi_flag AS (
  SELECT d.subject_id, d.hadm_id, 1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
  GROUP BY d.subject_id, d.hadm_id
),
joined AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.stay_id,
    h.mean_hr,
    IFNULL(m.has_mi, 0) AS has_mi
  FROM hr_per_stay AS h
  LEFT JOIN mi_flag AS m
    ON h.subject_id = m.subject_id AND h.hadm_id = m.hadm_id
)
SELECT
  CASE
    WHEN mean_hr < 60 THEN '<60'
    WHEN mean_hr >= 60 AND mean_hr <= 99 THEN '60-99'
    WHEN mean_hr >= 100 AND mean_hr <= 119 THEN '100-119'
    ELSE '>=120'
  END AS hr_category,
  COUNT(*) AS stay_count,
  100.0 * SUM(has_mi) / COUNT(*) AS mi_percent
FROM joined
GROUP BY hr_category
ORDER BY hr_category;