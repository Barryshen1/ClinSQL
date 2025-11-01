WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN p.dod IS NOT NULL AND DATETIME_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON
    a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND d.icd_code IN ('I460', 'I461', 'I469') -- Cardiac arrest codes
),

-- Get first ICU stay per admission
first_icu AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),

-- Get first lactate value in ICU
lactate_first AS (
  SELECT
    l.hadm_id,
    MIN(l.valuenum) AS first_lactate
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%lactate%'
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.hadm_id
),

-- Get first vital signs (HR, SBP)
vitals_first AS (
  SELECT
    c.stay_id,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN c.valuenum END) AS max_hr,
    MIN(CASE WHEN di.label = 'Arterial Blood Pressure systolic' THEN c.valuenum END) AS min_sbp
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    c.itemid = di.itemid
  WHERE
    di.label IN ('Heart Rate', 'Arterial Blood Pressure systolic')
    AND c.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
),

-- Composite risk score (proxy)
risk_score AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    COALESCE(l.first_lactate, 0) +
    COALESCE(v.max_hr / 100, 0) +
    COALESCE(100 - v.min_sbp, 0) AS risk_score_composite
  FROM
    cohort c
  LEFT JOIN
    lactate_first l
  ON
    c.hadm_id = l.hadm_id
  LEFT JOIN
    vitals_first v
  ON
    c.stay_id = v.stay_id
),

-- Add quartiles
cohort_with_quartiles AS (
  SELECT
    c.*,
    r.risk_score_composite,
    NTILE(4) OVER (ORDER BY r.risk_score_composite) AS risk_quartile
  FROM
    cohort c
  JOIN
    risk_score r
  ON
    c.hadm_id = r.hadm_id
),

-- Baseline 30-day mortality for entire cohort
baseline_mortality AS (
  SELECT
    AVG(mortality_30d) AS baseline_30d_mortality
  FROM
    cohort_with_quartiles
),

-- Complications
complications AS (
  SELECT
    dx.hadm_id,
    MAX(CASE WHEN dx.icd_code IN ('I63', 'I64', 'G931') THEN 1 ELSE 0 END) AS neuro_complication,
    MAX(CASE WHEN dx.icd_code IN ('I47', 'I49', 'I50') THEN 1 ELSE 0 END) AS cardio_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  GROUP BY
    dx.hadm_id
)

-- Final aggregation by quartile
SELECT
  q.risk_quartile,
  AVG(q.mortality_30d) AS mortality_30d_rate,
  AVG(COALESCE(c.neuro_complication, 0)) AS neuro_complication_rate,
  AVG(COALESCE(c.cardio_complication, 0)) AS cardio_complication_rate,
  APPROX_QUANTILES(CASE WHEN q.mortality_30d = 0 THEN q.los_days ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los,
  b.baseline_30d_mortality
FROM
  cohort_with_quartiles q
LEFT JOIN
  complications c
ON
  q.hadm_id = c.hadm_id
CROSS JOIN
  baseline_mortality b
GROUP BY
  q.risk_quartile, b.baseline_30d_mortality
ORDER BY
  q.risk_quartile;