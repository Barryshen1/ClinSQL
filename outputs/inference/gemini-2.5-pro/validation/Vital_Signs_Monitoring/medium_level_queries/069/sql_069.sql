WITH cohort AS (
  -- Step 1: Identify ICU stays for female patients aged 41-51
  SELECT
    p.subject_id,
    p.gender,
    i.hadm_id,
    i.stay_id,
    i.intime,
    -- Calculate age at ICU admission
    DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age AS age_at_icu_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND (DATETIME_DIFF(i.intime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 41 AND 51
),
rr_avg_first_48h AS (
  -- Step 2: Calculate average RR in the first 48 hours for each stay in the cohort
  SELECT
    c.stay_id,
    c.hadm_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    cohort AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220210 -- Respiratory Rate
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 -- Physiologically plausible values
  GROUP BY
    c.stay_id, c.hadm_id
),
rr_categorized AS (
  -- Step 3: Categorize stays based on the average RR
  SELECT
    r.stay_id,
    r.hadm_id,
    CASE
      WHEN r.avg_rr < 12 THEN 'RR < 12'
      WHEN r.avg_rr >= 12 AND r.avg_rr <= 20 THEN 'RR 12-20'
      WHEN r.avg_rr >= 21 AND r.avg_rr <= 29 THEN 'RR 21-29'
      WHEN r.avg_rr >= 30 THEN 'RR >= 30'
      ELSE NULL
    END AS rr_category
  FROM
    rr_avg_first_48h AS r
),
stroke_admissions AS (
  -- Step 4: Identify all hospital admissions with a stroke diagnosis
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for cerebrovascular disease
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432', '433', '434', '435', '436', '437'))
    -- ICD-10 codes for cerebrovascular disease and TIA
    OR (icd_version = 10 AND (
        SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69')
        OR SUBSTR(icd_code, 1, 3) = 'G45' -- Transient ischemic attack
    ))
)
-- Step 5 & 6: Combine, aggregate, and calculate final metrics
SELECT
  rc.rr_category,
  COUNT(DISTINCT rc.stay_id) AS number_of_stays,
  COUNT(DISTINCT CASE WHEN sa.hadm_id IS NOT NULL THEN rc.stay_id END) AS number_of_stroke_stays,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN sa.hadm_id IS NOT NULL THEN rc.stay_id END) * 100.0, COUNT(DISTINCT rc.stay_id)) AS stroke_rate_percent
FROM
  rr_categorized AS rc
LEFT JOIN
  stroke_admissions AS sa
  ON rc.hadm_id = sa.hadm_id
WHERE
  rc.rr_category IS NOT NULL
GROUP BY
  rc.rr_category
ORDER BY
  -- Order by the lower bound of the RR range for logical sorting
  CASE
    WHEN rc.rr_category = 'RR < 12' THEN 1
    WHEN rc.rr_category = 'RR 12-20' THEN 2
    WHEN rc.rr_category = 'RR 21-29' THEN 3
    WHEN rc.rr_category = 'RR >= 30' THEN 4
  END;