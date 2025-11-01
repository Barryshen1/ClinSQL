WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    a.hospital_expire_flag,
    i.los AS icu_los
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
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(dd.long_title) LIKE '%hyperosmolar hyperglycemic%'
),

lab_instability AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  WHERE
    l.charttime >= c.intime
    AND l.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND l.flag IS NOT NULL
    AND LOWER(l.flag) != 'normal'
  GROUP BY
    c.hadm_id
),

percentile_75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS threshold
  FROM
    lab_instability
),

high_instability_admissions AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    lab_instability li
  ON
    c.hadm_id = li.hadm_id
  CROSS JOIN
    percentile_75 p
  WHERE
    li.instability_score >= p.threshold
),

critical_labs AS (
  SELECT
    l.hadm_id,
    MAX(CASE
      WHEN l.itemid IN (50813, 50960) AND l.valuenum > 4 THEN 1  -- lactate
      WHEN l.itemid IN (50822, 50971) AND (l.valuenum < 2.5 OR l.valuenum > 6.5) THEN 1  -- potassium
      ELSE 0
    END) AS has_critical
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE
    l.valuenum IS NOT NULL
  GROUP BY
    l.hadm_id
),

high_instability_with_critical AS (
  SELECT
    h.hadm_id,
    h.hospital_expire_flag,
    h.icu_los,
    COALESCE(c.has_critical, 0) AS has_critical
  FROM
    high_instability_admissions h
  LEFT JOIN
    critical_labs c
  ON
    h.hadm_id = c.hadm_id
),

all_cohort_critical AS (
  SELECT
    c.hadm_id,
    COALESCE(cr.has_critical, 0) AS has_critical
  FROM
    cohort c
  LEFT JOIN
    critical_labs cr
  ON
    c.hadm_id = cr.hadm_id
)

SELECT
  -- Mortality
  AVG(h.hospital_expire_flag) AS mortality_rate,

  -- Mean ICU LOS
  AVG(h.icu_los) AS mean_icu_los_days,

  -- Critical lab rate in high instability group
  AVG(h.has_critical) AS high_instability_critical_lab_rate,

  -- Critical lab rate in general cohort
  (SELECT AVG(has_critical) FROM all_cohort_critical) AS general_critical_lab_rate

FROM
  high_instability_with_critical h;