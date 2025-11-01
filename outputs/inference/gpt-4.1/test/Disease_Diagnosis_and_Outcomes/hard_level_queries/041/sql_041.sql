WITH cohort AS (
  -- Step 1: Identify male patients age 68-78 with ICH diagnosis and ICU transfer
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    INNER JOIN (
      -- Find admissions with ICU transfer
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.transfers`
      WHERE careunit LIKE '%ICU%'
        AND eventtype = 'transfer'
    ) t
      ON a.hadm_id = t.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND (
      LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(dd.long_title) LIKE '%ich%'
    )
),
aki_flags AS (
  -- Step 2: Flag AKI per admission
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (
          (icd_version = 9 AND (icd_code LIKE '584%' OR icd_code = '593.9'))
          OR (icd_version = 10 AND icd_code LIKE 'N17%')
        )
        THEN 1 ELSE 0 END
    ) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
ards_flags AS (
  -- Step 2: Flag ARDS per admission
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (
          (icd_version = 9 AND (icd_code = '518.82' OR icd_code = '518.5'))
          OR (icd_version = 10 AND icd_code = 'J80')
        )
        THEN 1 ELSE 0 END
    ) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
outcomes AS (
  -- Step 3: Merge flags and calculate outcomes
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.anchor_age,
    c.gender,
    IF(aki.has_aki IS NULL, 0, aki.has_aki) AS has_aki,
    IF(ards.has_ards IS NULL, 0, ards.has_ards) AS has_ards,
    -- 30-day mortality: died within 30 days of admission
    CASE
      WHEN c.deathtime IS NOT NULL AND DATETIME_DIFF(c.deathtime, c.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Survival days (for decedents)
    CASE
      WHEN c.deathtime IS NOT NULL THEN DATETIME_DIFF(c.deathtime, c.admittime, DAY)
      ELSE NULL
    END AS survival_days,
    -- Composite risk score: sum of binary indicators
    (IF(aki.has_aki IS NULL, 0, aki.has_aki)
     + IF(ards.has_ards IS NULL, 0, ards.has_ards)
     + CASE WHEN c.deathtime IS NOT NULL AND DATETIME_DIFF(c.deathtime, c.admittime, DAY) <= 30 THEN 1 ELSE 0 END
    ) AS composite_risk_score
  FROM cohort c
  LEFT JOIN aki_flags aki ON c.hadm_id = aki.hadm_id
  LEFT JOIN ards_flags ards ON c.hadm_id = ards.hadm_id
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(SUM(mortality_30d) / COUNT(*), 3) AS mortality_30d_rate,
  ROUND(SUM(has_aki) / COUNT(*), 3) AS aki_rate,
  ROUND(SUM(has_ards) / COUNT(*), 3) AS ards_rate,
  -- Composite risk score percentiles
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(1)] AS composite_risk_score_25th,
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(2)] AS composite_risk_score_50th,
  APPROX_QUANTILES(composite_risk_score, 4)[OFFSET(3)] AS composite_risk_score_75th,
  -- Median survival among decedents
  APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days_decedents
FROM outcomes;