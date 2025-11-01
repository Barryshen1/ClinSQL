WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(d.long_title) LIKE '%asthma%'
    AND LOWER(d.long_title) LIKE '%exacerbation%'
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
    l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL
    AND LOWER(l.flag) != 'normal'
  GROUP BY
    c.hadm_id
),

instability_with_percentile AS (
  SELECT
    hadm_id,
    instability_score,
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_instability
  FROM
    lab_instability
),

top_decile AS (
  SELECT
    hadm_id,
    instability_score
  FROM
    instability_with_percentile
  WHERE
    instability_score >= (
      SELECT
        p90_instability
      FROM
        instability_with_percentile
      LIMIT 1
    )
),

top_decile_stats AS (
  SELECT
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(c.los_days) AS mean_los,
    AVG(t.instability_score) AS avg_critical_labs
  FROM
    top_decile t
  JOIN
    cohort c
  ON
    t.hadm_id = c.hadm_id
),

age_matched_males AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

age_matched_stats AS (
  SELECT
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(los_days) AS mean_los
  FROM
    age_matched_males
)

SELECT
  td.mortality AS top_decile_mortality,
  td.mean_los AS top_decile_mean_los,
  td.avg_critical_labs AS top_decile_avg_critical_labs,
  am.mortality AS age_matched_mortality,
  am.mean_los AS age_matched_mean_los
FROM
  top_decile_stats td
CROSS JOIN
  age_matched_stats am;