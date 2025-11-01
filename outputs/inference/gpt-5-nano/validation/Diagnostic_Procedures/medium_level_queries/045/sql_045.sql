WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.subject_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND dd.long_title LIKE '%deep vein thrombosis%'
    AND a.dischtime IS NOT NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
icu_flags AS (
  SELECT c.hadm_id,
         MAX(CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_icu
  FROM cohort AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),
imaging_events AS (
  SELECT c.hadm_id,
         ic.has_icu,
         CASE
           WHEN c.los_days BETWEEN 1 AND 4 THEN '1-4'
           WHEN c.los_days BETWEEN 5 AND 8 THEN '5-8'
           ELSE NULL
         END AS los_bucket,
         COUNT(DISTINCT ce.charttime) AS imaging_count
  FROM cohort AS c
  JOIN icu_flags ic ON ic.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = c.hadm_id
   AND ce.charttime >= c.admittime
   AND ce.charttime <= c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS ditem
    ON ce.itemid = ditem.itemid
  WHERE ditem.category = 'Imaging'
  GROUP BY c.hadm_id, ic.has_icu, los_bucket
)
SELECT
  CASE WHEN has_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
  los_bucket,
  COUNT(*) AS admissions_count,
  AVG(imaging_count) AS mean_noninvasive_diagnostics_per_admission
FROM imaging_events
WHERE los_bucket IS NOT NULL
GROUP BY icu_status, los_bucket
ORDER BY icu_status, los_bucket;