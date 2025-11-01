WITH cohort_stays AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
    AND UPPER(p.gender) = 'F'
),

-- 2) Per-stay average heart rate in first 48 hours
hr_per_stay AS (
  SELECT
    cs.stay_id,
    cs.hadm_id,
    cs.subject_id,
    AVG(ce.valuenum) AS hr_mean
  FROM cohort_stays AS cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = cs.subject_id
   AND ce.hadm_id = cs.hadm_id
   AND ce.stay_id = cs.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%heart rate%'
    AND ce.charttime BETWEEN (
          SELECT intime
          FROM `physionet-data.mimiciv_3_1_icu.icustays`
          WHERE stay_id = cs.stay_id
        ) AND TIMESTAMP_ADD(
              (SELECT intime
               FROM `physionet-data.mimiciv_3_1_icu.icustays`
               WHERE stay_id = cs.stay_id),
              INTERVAL 48 HOUR
            )
  GROUP BY cs.stay_id, cs.hadm_id, cs.subject_id
),

-- 3) Categorize HR and prepare for distribution
hr_category AS (
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    hr_mean,
    CASE
      WHEN hr_mean < 60 THEN '<60'
      WHEN hr_mean >= 60 AND hr_mean <= 99 THEN '60-99'
      WHEN hr_mean >= 100 AND hr_mean <= 119 THEN '100-119'
      ELSE '>=120'
    END AS hr_category
  FROM hr_per_stay
  WHERE hr_mean IS NOT NULL
),

-- 4) AKI by admission (N17* ICD codes)
aki_by_hadm AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS aki_present
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)

-- 5) Final aggregation: distribution by HR category and AKI rate by category
SELECT
  h.hr_category,
  COUNT(*) AS n_stays,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
  ROUND(100.0 * COALESCE(SUM(a.aki_present), 0) / COUNT(*), 2) AS aki_rate_percent
FROM hr_category AS h
LEFT JOIN aki_by_hadm AS a
  ON h.hadm_id = a.hadm_id
GROUP BY h.hr_category
ORDER BY
  CASE
    WHEN h.hr_category = '<60' THEN 1
    WHEN h.hr_category = '60-99' THEN 2
    WHEN h.hr_category = '100-119' THEN 3
    WHEN h.hr_category = '>=120' THEN 4
  END;