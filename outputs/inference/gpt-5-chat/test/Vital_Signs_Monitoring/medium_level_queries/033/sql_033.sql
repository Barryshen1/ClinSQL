WITH cohort AS (
  SELECT p.subject_id, i.hadm_id, i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
),
hr_mean AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    AVG(e.valuenum) AS mean_hr
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` e
    ON c.stay_id = e.stay_id
  WHERE e.itemid = 220045 -- Heart Rate
    AND e.valuenum IS NOT NULL
    AND e.valuenum > 0
    AND e.valuenum < 300
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
hr_cat AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    mean_hr,
    CASE
      WHEN mean_hr < 60 THEN '<60'
      WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN mean_hr >= 120 THEN '>=120'
    END AS hr_category
  FROM hr_mean
),
ami_flags AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 9 AND icd_code LIKE '410%')
          OR (icd_version = 10 AND icd_code LIKE 'I21%')
        THEN 1 ELSE 0
      END
    ) AS acute_mi_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT
  hr_category,
  COUNT(*) AS stay_count,
  SUM(CASE WHEN acute_mi_flag = 1 THEN 1 ELSE 0 END) AS stays_with_ami,
  ROUND(100.0 * SUM(CASE WHEN acute_mi_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_with_ami
FROM hr_cat
LEFT JOIN ami_flags
  ON hr_cat.hadm_id = ami_flags.hadm_id
GROUP BY hr_category
ORDER BY
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;