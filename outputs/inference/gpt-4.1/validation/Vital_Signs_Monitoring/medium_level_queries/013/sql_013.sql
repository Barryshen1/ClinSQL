WITH
-- 1. Get SpO2 itemids
spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),

-- 2. Get male ICU stays aged 51–61
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
),

-- 3. Get SpO2 measurements in first 48h of ICU stay
spo2_first48 AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  INNER JOIN spo2_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

-- 4. Compute average SpO2 per stay (exclude stays with no measurements)
avg_spo2_per_stay AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_spo2
  FROM spo2_first48
  GROUP BY stay_id, subject_id, hadm_id
),

-- 5. Categorize average SpO2
spo2_categorized AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    avg_spo2,
    CASE
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 >= 90 AND avg_spo2 < 93 THEN '90-92'
      WHEN avg_spo2 >= 93 AND avg_spo2 <= 95 THEN '93-95'
      WHEN avg_spo2 > 95 THEN '>95'
      ELSE 'Unknown'
    END AS spo2_category
  FROM avg_spo2_per_stay
),

-- 6. Identify AKI diagnosis per stay (via hadm_id)
aki_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-10: N17.x
    (icd_version = 10 AND (icd_code LIKE 'N17%' ))
    -- ICD-9: 584.x
    OR (icd_version = 9 AND (icd_code LIKE '584%'))
),

-- 7. Mark AKI per stay
spo2_with_aki AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.avg_spo2,
    s.spo2_category,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM spo2_categorized s
  LEFT JOIN aki_stays a
    ON s.hadm_id = a.hadm_id
)

-- 8. Aggregate: per SpO2 category, count stays, unique patients, AKI rate
SELECT
  spo2_category,
  COUNT(*) AS num_stays,
  COUNT(DISTINCT subject_id) AS num_patients,
  SUM(has_aki) AS num_aki_stays,
  ROUND(SUM(has_aki) / COUNT(*), 3) AS aki_rate
FROM spo2_with_aki
WHERE spo2_category != 'Unknown'
GROUP BY spo2_category
ORDER BY
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
    ELSE 5
  END
;