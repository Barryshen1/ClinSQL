WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code IN ('J440', 'J441'))
          OR
          (d.icd_version = 9 AND d.icd_code = '49121')
        )
    )
),

cohort_with_quartile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY age) AS quartile
  FROM cohort
),

complications AS (
  SELECT
    c.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.subject_id = c.subject_id
          AND d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
            OR
            (d.icd_version = 9 AND d.icd_code = '51881')
          )
      ) THEN 1
      ELSE 0
    END AS major_complication
  FROM cohort_with_quartile c
),

metrics AS (
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL
        AND dod <= DATE_ADD(DATE(admittime), INTERVAL 90 DAY)
      THEN 1.0
      ELSE 0.0
    END AS ninetyd_mort,
    major_complication * 1.0 AS major_comp_rate,
    CASE
      WHEN dod IS NULL
        OR dod > DATE_ADD(DATE(admittime), INTERVAL 90 DAY)
      THEN TIMESTAMP_DIFF(dischtime, admittime, DAY)
      ELSE NULL
    END AS survivor_los_days
  FROM complications
),

broader_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.dod,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
),

broader_mortality AS (
  SELECT
    COUNT(*) AS total_admissions,
    COUNTIF(
      dod IS NOT NULL AND dod <= DATE_ADD(DATE(admittime), INTERVAL 90 DAY)
    ) AS total_deaths
  FROM broader_cohort
)

SELECT
  m.quartile,
  COUNT(*) AS n_per_quartile,
  AVG(m.ninetyd_mort) AS ninetyd_mortality_rate,
  AVG(m.major_comp_rate) AS major_complication_rate,
  APPROX_QUANTILES(m.survivor_los_days, 2)[OFFSET(1)] AS median_survivor_los_days,
  bm.total_deaths * 1.0 / bm.total_admissions AS broader_75_85_female_ninetyd_mortality
FROM metrics m
CROSS JOIN broader_mortality bm
GROUP BY m.quartile, bm.total_deaths, bm.total_admissions
ORDER BY m.quartile;