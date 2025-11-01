WITH
-- Get male patients aged 40-50
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    male_patients p ON s.subject_id = p.subject_id
),

-- Get SBP measurements in first 48 hours of each stay
sbp_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Systolic Blood Pressure'
    AND ce.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Calculate mean SBP per stay
mean_sbp_per_stay AS (
  SELECT
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM
    sbp_measurements
  GROUP BY
    stay_id
),

-- Categorize SBP
sbp_categories AS (
  SELECT
    stay_id,
    mean_sbp,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category
  FROM
    mean_sbp_per_stay
),

-- Get MI diagnoses
mi_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410.%')
    OR (d.icd_version = 9 AND d.icd_code = '412')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21.%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I22.%')
),

-- Join with ICU stays to get MI status
stays_with_mi AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    CASE WHEN m.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM
    icu_stays s
  LEFT JOIN
    mi_diagnoses m ON s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
),

-- Final analysis
final_analysis AS (
  SELECT
    sc.sbp_category,
    COUNT(DISTINCT sc.stay_id) AS total_stays,
    SUM(sm.has_mi) AS mi_stays
  FROM
    sbp_categories sc
  JOIN
    stays_with_mi sm ON sc.stay_id = sm.stay_id
  GROUP BY
    sc.sbp_category
)

-- Calculate percentages and MI rates
SELECT
  sbp_category,
  total_stays,
  ROUND(total_stays * 100.0 / SUM(total_stays) OVER(), 2) AS percent_of_stays,
  ROUND(mi_stays * 100.0 / total_stays, 2) AS mi_rate_per_100_stays
FROM
  final_analysis
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    ELSE 3
  END;