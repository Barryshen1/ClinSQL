WITH rr_itemids AS (
  -- Get itemids for Respiratory Rate from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),

female_41_51_icu AS (
  -- Get ICU stays for female patients aged 41-51
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 41 AND 51
),

rr_first_48h AS (
  -- Get RR measurements in first 48h of each ICU stay
  SELECT
    f.stay_id,
    f.hadm_id,
    f.subject_id,
    ce.charttime,
    ce.valuenum
  FROM female_41_51_icu f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON f.stay_id = ce.stay_id
  JOIN rr_itemids ri
    ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= f.intime
    AND ce.charttime < DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
),

avg_rr_per_stay AS (
  -- Calculate per-stay average RR
  SELECT
    stay_id,
    hadm_id,
    subject_id,
    AVG(valuenum) AS avg_rr
  FROM rr_first_48h
  GROUP BY stay_id, hadm_id, subject_id
),

stroke_admissions AS (
  -- Identify admissions with stroke diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- ICD-10: I60.x, I61.x, I63.x, I64.x
    (d.icd_version = 10 AND (
      REGEXP_CONTAINS(d.icd_code, r'^I60') OR
      REGEXP_CONTAINS(d.icd_code, r'^I61') OR
      REGEXP_CONTAINS(d.icd_code, r'^I63') OR
      REGEXP_CONTAINS(d.icd_code, r'^I64')
    ))
    OR
    -- ICD-9: 430.x, 431.x, 434.x, 436.x
    (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^430') OR
      REGEXP_CONTAINS(d.icd_code, r'^431') OR
      REGEXP_CONTAINS(d.icd_code, r'^434') OR
      REGEXP_CONTAINS(d.icd_code, r'^436')
    ))
  )
)

SELECT
  CASE
    WHEN avg_rr < 12 THEN '<12'
    WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
    WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
    WHEN avg_rr >= 30 THEN '>=30'
    ELSE 'Unknown'
  END AS rr_bin,
  COUNT(*) AS n_stays,
  SUM(CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_stroke,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END), COUNT(*)) * 100, 1) AS stroke_rate_percent
FROM avg_rr_per_stay a
LEFT JOIN stroke_admissions s
  ON a.hadm_id = s.hadm_id
GROUP BY rr_bin
ORDER BY
  CASE rr_bin
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
    ELSE 5
  END;