WITH cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age BETWEEN 62 AND 72
),
heart_rate AS (
  SELECT
    fc.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fc.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'  -- ItemID 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fc.intime AND fc.outtime
  GROUP BY fc.stay_id
),
hr_categories AS (
  SELECT
    stay_id,
    mean_hr,
    CASE
      WHEN mean_hr < 60 THEN '<60'
      WHEN mean_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN mean_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN mean_hr >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_category
  FROM heart_rate
),
acute_mi AS (
  SELECT
    fc.hadm_id,
    MAX(
      CASE
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
             (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        THEN 1
        ELSE 0
      END
    ) AS acute_mi_flag
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fc.hadm_id = d.hadm_id
  GROUP BY fc.hadm_id
)
SELECT
  hc.hr_category,
  COUNT(DISTINCT hc.stay_id) AS total_stays,
  ROUND(100 * AVG(ami.acute_mi_flag), 2) AS percent_with_acute_mi
FROM hr_categories hc
INNER JOIN filtered_cohort fc
  ON hc.stay_id = fc.stay_id
INNER JOIN acute_mi ami
  ON fc.hadm_id = ami.hadm_id
WHERE hc.hr_category IS NOT NULL
GROUP BY hc.hr_category
ORDER BY
  CASE hc.hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;