WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
),

hr_first48 AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.stay_id
),

hr_category AS (
  SELECT
    stay_id,
    avg_hr,
    CASE
      WHEN avg_hr < 60 THEN '<60'
      WHEN avg_hr >= 60 AND avg_hr <= 99 THEN '60–99'
      WHEN avg_hr >= 100 AND avg_hr <= 119 THEN '100–119'
      WHEN avg_hr >= 120 THEN '≥120'
    END AS hr_bin
  FROM
    hr_first48
),

aki_flag AS (
  SELECT DISTINCT
    c.stay_id,
    1 AS aki
  FROM
    cohort c
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
    (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
    OR
    (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
),

stay_with_flags AS (
  SELECT
    h.stay_id,
    h.hr_bin,
    COALESCE(a.akI, 0) AS aki
  FROM
    hr_category h
  LEFT JOIN
    aki_flag a
  ON
    h.stay_id = a.stay_id
),

summary AS (
  SELECT
    hr_bin,
    COUNT(*) AS n_stays,
    SUM(aki) AS n_aki
  FROM
    stay_with_flags
  GROUP BY
    hr_bin
)

SELECT
  hr_bin,
  ROUND(100.0 * n_stays / SUM(n_stays) OVER (), 2) AS percent_distribution,
  ROUND(100.0 * n_aki / n_stays, 2) AS aki_rate_percent
FROM
  summary
ORDER BY
  CASE hr_bin
    WHEN '<60' THEN 1
    WHEN '60–99' THEN 2
    WHEN '100–119' THEN 3
    WHEN '≥120' THEN 4
  END;