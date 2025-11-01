WITH cohort_base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    p.dod,
    a.hospital_expire_flag,
    i.stay_id,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),

dka_patients AS (
  SELECT DISTINCT
    cb.*
  FROM
    cohort_base cb
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    cb.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('E10.11', 'E11.11') -- DKA
),

general_cohort AS (
  SELECT DISTINCT
    cb.*
  FROM
    cohort_base cb
),

dka_with_comorbidities AS (
  SELECT
    dka.*,
    MAX(CASE WHEN dd.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN dd.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM
    dka_patients dka
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    dka.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  GROUP BY
    dka.subject_id, dka.hadm_id, dka.anchor_age, dka.admittime, dka.dischtime, dka.dod, dka.hospital_expire_flag, dka.stay_id, dka.icu_los
),

general_with_comorbidities AS (
  SELECT
    gen.*,
    MAX(CASE WHEN dd.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN dd.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM
    general_cohort gen
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    gen.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  GROUP BY
    gen.subject_id, gen.hadm_id, gen.anchor_age, gen.admittime, gen.dischtime, gen.dod, gen.hospital_expire_flag, gen.stay_id, gen.icu_los
),

dka_outcomes AS (
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL AND DATETIME_DIFF(dod, admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    anchor_age AS risk_score_proxy
  FROM
    dka_with_comorbidities
),

general_outcomes AS (
  SELECT
    *,
    anchor_age AS risk_score_proxy
  FROM
    general_with_comorbidities
),

dka_stats AS (
  SELECT
    AVG(risk_score_proxy) AS mean_risk_score,
    AVG(mortality_30d) AS mortality_30d_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN icu_los ELSE NULL END) AS survivor_mean_los
  FROM
    dka_outcomes
),

general_median_risk AS (
  SELECT
    APPROX_QUANTILES(risk_score_proxy, 100)[OFFSET(50)] AS median_risk_general
  FROM
    general_outcomes
)

SELECT
  ds.mean_risk_score,
  ds.mortality_30d_rate,
  ds.aki_rate,
  ds.ards_rate,
  ds.survivor_mean_los,
  gmr.median_risk_general AS percentile_50_risk_general
FROM
  dka_stats ds
CROSS JOIN
  general_median_risk gmr;