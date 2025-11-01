WITH
-- 1. Get cardiac arrest ICD codes (ICD-9: 427.5, ICD-10: I46.x)
cardiac_arrest_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code = '4275') -- 427.5 stored as 4275
    OR (icd_version = 10 AND (icd_code LIKE 'I46%' OR icd_code LIKE 'I490%' OR icd_code LIKE 'I472%'))
),

-- 2. Get all ICU stays for male patients aged 55–65 with post–cardiac arrest
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN cardiac_arrest_codes cac
    ON diag.icd_code = cac.icd_code AND diag.icd_version = cac.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
),

-- 3. Get itemids for vital signs
vital_items AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) IN (
      'heart rate',
      'hr',
      'systolic blood pressure',
      'sbp',
      'respiratory rate',
      'rr',
      'spo2',
      'o2 saturation',
      'temperature',
      'temp'
    )
),

-- 4. For each ICU stay, count instability events in first 24h
instability_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    vi.label,
    ce.valuenum,
    -- Instability flag per vital sign
    CASE
      WHEN vi.label IN ('heart rate', 'hr') AND (ce.valuenum < 50 OR ce.valuenum > 100) THEN 1
      WHEN vi.label IN ('systolic blood pressure', 'sbp') AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN vi.label IN ('respiratory rate', 'rr') AND (ce.valuenum < 12 OR ce.valuenum > 24) THEN 1
      WHEN vi.label IN ('spo2', 'o2 saturation') AND (ce.valuenum < 92) THEN 1
      WHEN vi.label IN ('temperature', 'temp') AND (ce.valuenum < 36 OR ce.valuenum > 38) THEN 1
      ELSE 0
    END AS instability
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_items vi
    ON ce.itemid = vi.itemid
  JOIN cohort c
    ON ce.stay_id = c.stay_id
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

-- 5. Aggregate instability score per ICU stay
instability_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    c.anchor_age,
    c.hospital_expire_flag,
    SUM(e.instability) AS instability_score
  FROM cohort c
  LEFT JOIN instability_events e
    ON c.stay_id = e.stay_id
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.los, c.anchor_age, c.hospital_expire_flag
),

-- 6. Calculate percentile of score 70
score_percentile AS (
  SELECT
    COUNTIF(isc.instability_score <= 70) / COUNT(*) * 100 AS percentile_70
  FROM instability_score isc
),

-- 7. Get top decile (most unstable 10%)
top_decile AS (
  SELECT *
  FROM (
    SELECT
      *,
      NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
    FROM instability_score
  )
  WHERE decile = 1
)

-- 8. Final output
SELECT
  -- Part 1: Percentile of score 70
  (SELECT percentile_70 FROM score_percentile) AS percentile_of_score_70,
  -- Part 2: Mean ICU LOS and mortality for most unstable decile
  (SELECT AVG(los) FROM top_decile) AS mean_icu_los_top_decile,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM top_decile) AS mortality_rate_top_decile;