WITH sbp_measurements AS (
  -- 1. Extract systolic blood pressure events in the first 48h of each ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = icu.subject_id
     AND ce.hadm_id    = icu.hadm_id
     AND ce.stay_id    = icu.stay_id
     -- Restrict to first 48 hours
     AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
      -- Identify systolic blood pressure
      AND LOWER(di.label) LIKE '%systolic%blood pressure%'
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
),

mi_flags AS (
  -- 2. Flag admissions with a myocardial infarction diagnosis (ICD-9 code 410%)
  SELECT
    DISTINCT hadm_id,
    1 AS mi_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_version = 9
    AND icd_code LIKE '410%'
),

eligible_stays AS (
  -- 3. Restrict to male patients aged 40–50
  SELECT
    sbp.subject_id,
    sbp.hadm_id,
    sbp.stay_id,
    sbp.mean_sbp,
    COALESCE(m.mi_flag, 0) AS mi_flag
  FROM
    sbp_measurements sbp
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON sbp.subject_id = p.subject_id
  LEFT JOIN
    mi_flags m
      ON sbp.hadm_id = m.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

categorized AS (
  -- 4. Categorize mean SBP
  SELECT
    *,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140–159'
      ELSE '>=160'
    END AS sbp_category
  FROM
    eligible_stays
),

aggregated AS (
  -- 5. Aggregate counts and MI events per SBP category
  SELECT
    sbp_category,
    COUNT(*) AS n_stays,
    SUM(mi_flag) AS n_mi
  FROM
    categorized
  GROUP BY
    sbp_category
),

totals AS (
  -- 6. Total number of eligible stays
  SELECT
    COUNT(*) AS total_stays
  FROM
    categorized
)

-- 7. Final metrics: percent of stays and MI rate
SELECT
  a.sbp_category,
  a.n_stays,
  ROUND(100.0 * a.n_stays / t.total_stays, 2) AS pct_of_stays,
  a.n_mi,
  ROUND(100.0 * a.n_mi / a.n_stays, 2) AS mi_rate_pct
FROM
  aggregated a
  CROSS JOIN totals t
ORDER BY
  -- Ensure the logical order of SBP categories
  CASE
    WHEN sbp_category = '<140' THEN 1
    WHEN sbp_category = '140–159' THEN 2
    WHEN sbp_category = '>=160' THEN 3
    ELSE 4
  END;