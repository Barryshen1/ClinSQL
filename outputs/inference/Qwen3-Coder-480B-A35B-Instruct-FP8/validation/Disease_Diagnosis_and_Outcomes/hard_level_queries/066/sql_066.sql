WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod,
    COUNT(DISTINCT di.icd_code) AS comorbidity_score
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
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(d.long_title) LIKE '%pulmonary embolism%'
  GROUP BY
    p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.gender, p.dod
),

risk_percentiles AS (
  SELECT
    *,
    PERCENTILE_CONT(comorbidity_score, 0.75) OVER() AS score_75th,
    PERCENT_RANK() OVER(ORDER BY comorbidity_score) AS risk_percentile
  FROM cohort
),

high_risk AS (
  SELECT *
  FROM risk_percentiles
  WHERE comorbidity_score > score_75th
),

mortality_flag AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90d
  FROM high_risk
),

aki_ards AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(di.icd_code, r'^N17') THEN 1 ELSE 0 END) AS aki,
    MAX(CASE WHEN di.icd_code = 'J80' THEN 1 ELSE 0 END) AS ards
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN
    high_risk hr
  ON
    di.hadm_id = hr.hadm_id
  GROUP BY
    di.hadm_id
),

los_data AS (
  SELECT
    hr.hadm_id,
    SUM(icu.los) AS los
  FROM
    high_risk hr
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    hr.hadm_id = icu.hadm_id
  GROUP BY
    hr.hadm_id
),

survivors AS (
  SELECT
    m.*,
    COALESCE(a.aki, 0) AS aki,
    COALESCE(a.ards, 0) AS ards,
    l.los
  FROM
    mortality_flag m
  LEFT JOIN
    aki_ards a
  ON
    m.hadm_id = a.hadm_id
  LEFT JOIN
    los_data l
  ON
    m.hadm_id = l.hadm_id
  WHERE
    mortality_90d = 0
),

all_with_flags AS (
  SELECT
    m.*,
    COALESCE(a.aki, 0) AS aki,
    COALESCE(a.ards, 0) AS ards,
    l.los
  FROM
    mortality_flag m
  LEFT JOIN
    aki_ards a
  ON
    m.hadm_id = a.hadm_id
  LEFT JOIN
    los_data l
  ON
    m.hadm_id = l.hadm_id
)

SELECT
  AVG(comorbidity_score) AS mean_risk_score,
  AVG(mortality_90d) AS mortality_90d_rate,
  AVG(CASE WHEN mortality_90d = 0 THEN aki ELSE NULL END) AS aki_rate_among_survivors,
  AVG(CASE WHEN mortality_90d = 0 THEN ards ELSE NULL END) AS ards_rate_among_survivors,
  AVG(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END) AS mean_los_survivors,
  AVG(aki) AS aki_rate_all,
  AVG(ards) AS ards_rate_all,
  AVG(los) AS mean_los_all,
  AVG(risk_percentile) AS avg_risk_percentile
FROM
  all_with_flags;