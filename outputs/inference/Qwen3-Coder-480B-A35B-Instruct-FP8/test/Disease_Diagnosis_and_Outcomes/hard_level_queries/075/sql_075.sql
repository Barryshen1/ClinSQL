WITH cohort_female_44_54 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

hemorrhage_patients AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort_female_44_54 c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    c.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%intracranial hemorrhage%'
),

first_sofa_scores AS (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum) AS first_sofa
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%sofa%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

hemorrhage_with_sofa AS (
  SELECT
    h.*,
    s.first_sofa
  FROM
    hemorrhage_patients h
  LEFT JOIN
    first_sofa_scores s
  ON
    h.stay_id = s.stay_id
),

mortality_90d AS (
  SELECT
    *,
    CASE
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 90 THEN 1
      WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 90 THEN 1
      ELSE 0
    END AS mort_90d
  FROM
    hemorrhage_with_sofa
),

complications AS (
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code
    AND dx.icd_version = d.icd_version
  WHERE
    dx.seq_num > 1
    AND (
      LOWER(d.long_title) LIKE '%sepsis%'
      OR LOWER(d.long_title) LIKE '%pneumonia%'
      OR LOWER(d.long_title) LIKE '%organ failure%'
    )
),

hemorrhage_with_complications AS (
  SELECT
    m.*,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_complication
  FROM
    mortality_90d m
  LEFT JOIN
    complications c
  ON
    m.hadm_id = c.hadm_id
),

survivors AS (
  SELECT *
  FROM hemorrhage_with_complications
  WHERE hospital_expire_flag = 0
),

-- Percentile rank of SOFA score among all female 44–54
all_female_sofa AS (
  SELECT
    s.first_sofa
  FROM
    cohort_female_44_54 c
  LEFT JOIN
    first_sofa_scores s
  ON
    c.stay_id = s.stay_id
  WHERE
    s.first_sofa IS NOT NULL
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(first_sofa, 100) AS quantiles
  FROM
    all_female_sofa
)

SELECT
  -- Median (IQR) SOFA score
  APPROX_QUANTILES(first_sofa, 2)[ORDINAL(2)] AS median_sofa,
  APPROX_QUANTILES(first_sofa, 4)[ORDINAL(2)] AS q1_sofa,
  APPROX_QUANTILES(first_sofa, 4)[ORDINAL(4)] AS q3_sofa,

  -- 90-day mortality
  AVG(mort_90d) AS mortality_90d_rate,

  -- Complication rate
  AVG(has_complication) AS complication_rate,

  -- Median LOS of survivors
  APPROX_QUANTILES(hospital_los, 2)[ORDINAL(2)] AS median_survivor_los,

  -- Risk percentile
  (
    SELECT
      CAST(SUM(CASE WHEN afs.first_sofa <= h.first_sofa THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) * 100
    FROM
      all_female_sofa afs
    CROSS JOIN
      (SELECT first_sofa FROM hemorrhage_with_sofa WHERE first_sofa IS NOT NULL LIMIT 1) h
  ) AS risk_percentile

FROM
  hemorrhage_with_complications h
WHERE
  h.first_sofa IS NOT NULL;