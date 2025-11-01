WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'sbp'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),
icu_stays_filtered AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN filtered_patients p ON i.subject_id = p.subject_id
),
sbp_measurements AS (
  SELECT ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_itemids s ON ce.itemid = s.itemid
  JOIN icu_stays_filtered i ON ce.stay_id = i.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
),
mean_sbp_per_stay AS (
  SELECT stay_id, AVG(valuenum) AS mean_sbp
  FROM sbp_measurements
  GROUP BY stay_id
),
sbp_category AS (
  SELECT stay_id,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140–159'
      WHEN mean_sbp >= 160 THEN '≥160'
    END AS sbp_cat
  FROM mean_sbp_per_stay
),
mi_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(LOWER(d.long_title), r'myocardial infarction')
),
stay_with_mi AS (
  SELECT s.stay_id, s.sbp_cat,
    CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM sbp_category s
  JOIN icu_stays_filtered i ON s.stay_id = i.stay_id
  LEFT JOIN mi_diagnoses m ON i.hadm_id = m.hadm_id
),
aggregated AS (
  SELECT sbp_cat,
    COUNT(*) AS stay_count,
    SUM(has_mi) AS mi_count
  FROM stay_with_mi
  GROUP BY sbp_cat
)
SELECT
  sbp_cat,
  ROUND(stay_count * 100.0 / SUM(stay_count) OVER (), 2) AS percent_stays,
  ROUND(mi_count * 100.0 / stay_count, 2) AS mi_rate_percent
FROM aggregated
ORDER BY
  CASE sbp_cat
    WHEN '<140' THEN 1
    WHEN '140–159' THEN 2
    WHEN '≥160' THEN 3
  END;