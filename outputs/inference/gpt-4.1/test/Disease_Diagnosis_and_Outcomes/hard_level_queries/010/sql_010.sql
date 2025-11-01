WITH male_39_49 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

dka_hadm AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%ketoacidosis%'
),

drg_risk AS (
  SELECT
    hadm_id,
    MAX(CAST(drg_mortality AS INT64)) AS drg_mortality
  FROM
    `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY
    hadm_id
),

cardio_complications AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%myocardial infarct%'
    OR LOWER(dd.long_title) LIKE '%heart failure%'
    OR LOWER(dd.long_title) LIKE '%arrhythmia%'
    OR LOWER(dd.long_title) LIKE '%cardiac arrest%'
    OR LOWER(dd.long_title) LIKE '%stroke%'
    OR LOWER(dd.long_title) LIKE '%ischemia%'
),

neuro_complications AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%stroke%'
    OR LOWER(dd.long_title) LIKE '%seizure%'
    OR LOWER(dd.long_title) LIKE '%coma%'
    OR LOWER(dd.long_title) LIKE '%encephalopathy%'
),

cohort AS (
  SELECT
    m.*,
    CASE WHEN dka.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_dka,
    drg.drg_mortality,
    CASE WHEN cc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_cardio_complication,
    CASE WHEN nc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_neuro_complication,
    DATETIME_DIFF(m.dischtime, m.admittime, HOUR)/24.0 AS los_days,
    CASE
      WHEN m.dod IS NOT NULL AND DATETIME_DIFF(m.dod, m.admittime, DAY) <= 30 AND DATETIME_DIFF(m.dod, m.admittime, DAY) >= 0 THEN 1
      ELSE 0
    END AS died_30d
  FROM
    male_39_49 m
    LEFT JOIN dka_hadm dka ON m.hadm_id = dka.hadm_id
    LEFT JOIN drg_risk drg ON m.hadm_id = drg.hadm_id
    LEFT JOIN cardio_complications cc ON m.hadm_id = cc.hadm_id
    LEFT JOIN neuro_complications nc ON m.hadm_id = nc.hadm_id
),

summary AS (
  SELECT
    is_dka,
    COUNT(*) AS n_admissions,
    AVG(CAST(drg_mortality AS FLOAT64)) AS mean_drg_mortality,
    AVG(died_30d) AS mortality_30d_rate,
    AVG(has_cardio_complication) AS cardio_complication_rate,
    AVG(has_neuro_complication) AS neuro_complication_rate,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END) AS mean_survivor_los
  FROM
    cohort
  GROUP BY
    is_dka
),

percentile_calc AS (
  SELECT
    drg_mortality,
    PERCENT_RANK() OVER (ORDER BY drg_mortality) AS drg_mortality_percentile
  FROM
    cohort
  WHERE
    drg_mortality IS NOT NULL
),

dka_44yo AS (
  SELECT
    c.*
  FROM
    cohort c
  WHERE
    c.is_dka = 1
    AND c.anchor_age = 44
    -- If multiple, pick first admission
  ORDER BY
    c.admittime
  LIMIT 1
)

SELECT
  CASE WHEN s.is_dka = 1 THEN 'DKA' ELSE 'All Males 39-49' END AS group_label,
  s.n_admissions,
  s.mean_drg_mortality,
  s.mortality_30d_rate,
  s.cardio_complication_rate,
  s.neuro_complication_rate,
  s.mean_survivor_los,
  dka44.drg_mortality AS dka_44yo_drg_mortality,
  pc.drg_mortality_percentile AS dka_44yo_risk_percentile
FROM
  summary s
  LEFT JOIN dka_44yo dka44 ON s.is_dka = 1
  LEFT JOIN percentile_calc pc ON s.is_dka = 1 AND dka44.drg_mortality = pc.drg_mortality
ORDER BY
  s.is_dka DESC;