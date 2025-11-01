WITH cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.anchor_age BETWEEN 43 AND 53
    AND pat.gender = 'F'
    AND LOWER(d_dx.long_title) LIKE '%acute respiratory failure%'
),

map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),

hr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

vitals AS (
  SELECT
    ce.stay_id,
    COUNTIF(ce.itemid IN (SELECT itemid FROM map_itemids) AND ce.valuenum < 65) AS hypotension_episodes,
    COUNTIF(ce.itemid IN (SELECT itemid FROM hr_itemids) AND ce.valuenum > 130) AS tachycardia_episodes
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    cohort co
    ON ce.stay_id = co.stay_id
  WHERE
    ce.charttime >= co.intime
    AND ce.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.stay_id
),

vital_instability_index AS (
  SELECT
    co.stay_id,
    COALESCE(v.hypotension_episodes, 0) + COALESCE(v.tachycardia_episodes, 0) AS vital_instability_index
  FROM
    cohort co
  LEFT JOIN
    vitals v
    ON co.stay_id = v.stay_id
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(vii.vital_instability_index, 100)[OFFSET(95)] AS p95_vii,
    APPROX_QUANTILES(vii.vital_instability_index, 4)[OFFSET(3)] AS q3_vii
  FROM
    vital_instability_index AS vii
),

top_quartile AS (
  SELECT
    co.stay_id,
    co.icu_los,
    co.hospital_expire_flag,
    vi.vital_instability_index,
    COALESCE(v.hypotension_episodes > 0, FALSE) AS had_hypotension,
    COALESCE(v.tachycardia_episodes > 0, FALSE) AS had_tachycardia
  FROM
    cohort co
  JOIN
    vital_instability_index vi
    ON co.stay_id = vi.stay_id
  LEFT JOIN
    vitals v
    ON co.stay_id = v.stay_id
  CROSS JOIN
    percentiles p
  WHERE
    vi.vital_instability_index >= p.q3_vii
),

general_population AS (
  SELECT
    co.stay_id,
    co.icu_los,
    co.hospital_expire_flag,
    vi.vital_instability_index,
    COALESCE(v.hypotension_episodes > 0, FALSE) AS had_hypotension,
    COALESCE(v.tachycardia_episodes > 0, FALSE) AS had_tachycardia
  FROM
    cohort co
  JOIN
    vital_instability_index vi
    ON co.stay_id = vi.stay_id
  LEFT JOIN
    vitals v
    ON co.stay_id = v.stay_id
)

SELECT
  'Top Quartile' AS group_name,
  AVG(CAST(had_hypotension AS FLOAT64)) AS prop_hypotension,
  AVG(CAST(had_tachycardia AS FLOAT64)) AS prop_tachycardia,
  AVG(icu_los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  top_quartile

UNION ALL

SELECT
  'General ICU Population' AS group_name,
  AVG(CAST(had_hypotension AS FLOAT64)) AS prop_hypotension,
  AVG(CAST(had_tachycardia AS FLOAT64)) AS prop_tachycardia,
  AVG(icu_los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  general_population;