WITH
-- identify heart-rate itemids from d_items
hr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

-- cohort: female patients age 48-58 and their ICU stays
cohort_stays AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

-- per-stay average HR in first 48 hours
stay_avg_hr AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    AVG(ce.valuenum) AS avg_hr,
    COUNT(ce.valuenum) AS hr_count
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = cs.stay_id
  JOIN hr_items hi
    ON ce.itemid = hi.itemid
  WHERE ce.valuenum IS NOT NULL
    -- restrict to first 48 hours from ICU intime
    AND ce.charttime >= cs.intime
    AND ce.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id
  HAVING COUNT(ce.valuenum) > 0
),

-- admissions with AKI diagnosis (ICD-9: 584* ; ICD-10: N17*)
aki_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND UPPER(icd_code) LIKE 'N17%')
)

-- final aggregation: categorize avg_hr and compute counts + AKI rates
SELECT
  hr_category,
  COUNT(*) AS stays_in_category,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_cohort,
  ROUND(100.0 * SUM(CASE WHEN sa.hadm_id IN (SELECT hadm_id FROM aki_admissions) THEN 1 ELSE 0 END) / COUNT(*), 2) AS aki_rate_percent
FROM (
  SELECT
    sa.*,
    CASE
      WHEN sa.avg_hr < 60 THEN '<60'
      WHEN sa.avg_hr >= 60 AND sa.avg_hr <= 99 THEN '60-99'
      WHEN sa.avg_hr >= 100 AND sa.avg_hr <= 119 THEN '100-119'
      WHEN sa.avg_hr >= 120 THEN '>=120'
      ELSE 'unknown'
    END AS hr_category
  FROM stay_avg_hr sa
) sa
GROUP BY hr_category
ORDER BY
  -- ensure logical order of categories
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;