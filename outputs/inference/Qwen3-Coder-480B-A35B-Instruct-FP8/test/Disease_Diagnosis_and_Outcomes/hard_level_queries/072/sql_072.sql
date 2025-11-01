WITH cohort_acs AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
    CASE WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
),

comorbidities AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) IN (
      'hypertension', 'diabetes mellitus', 'chronic kidney disease', 'heart failure',
      'chronic obstructive pulmonary disease', 'stroke', 'myocardial infarction'
    )
  GROUP BY
    d.hadm_id
),

acs_with_risk AS (
  SELECT
    c.*,
    COALESCE(cm.comorbidity_count, 0) AS risk_score
  FROM
    cohort_acs c
  LEFT JOIN
    comorbidities cm ON c.hadm_id = cm.hadm_id
),

complications AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%cardiac arrest%' OR LOWER(dd.long_title) LIKE '%arrhythmia%' OR LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS cardiac_complication,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%stroke%' OR LOWER(dd.long_title) LIKE '%seizure%' OR LOWER(dd.long_title) LIKE '%encephalopathy%' THEN 1 ELSE 0 END) AS neurologic_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM cohort_acs)
  GROUP BY
    d.hadm_id
),

acs_final AS (
  SELECT
    a.*,
    COALESCE(c.cardiac_complication, 0) AS cardiac_complication,
    COALESCE(c.neurologic_complication, 0) AS neurologic_complication
  FROM
    acs_with_risk a
  LEFT JOIN
    complications c ON a.hadm_id = c.hadm_id
),

control_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
    CASE WHEN a.deathtime IS NOT NULL AND DATETIME_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id NOT IN (SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`)
    AND a.hadm_id NOT IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
    )
),

control_comorbidities AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) IN (
      'hypertension', 'diabetes mellitus', 'chronic kidney disease', 'heart failure',
      'chronic obstructive pulmonary disease', 'stroke', 'myocardial infarction'
    )
    AND d.hadm_id IN (SELECT hadm_id FROM control_cohort)
  GROUP BY
    d.hadm_id
),

control_final AS (
  SELECT
    c.*,
    COALESCE(cm.comorbidity_count, 0) AS risk_score
  FROM
    control_cohort c
  LEFT JOIN
    control_comorbidities cm ON c.hadm_id = cm.hadm_id
)

SELECT
  'ACS Cohort' AS cohort_type,
  AVG(risk_score) AS mean_risk_score,
  AVG(mortality_30d) AS mortality_30d_rate,
  AVG(cardiac_complication) AS cardiac_complication_rate,
  AVG(neurologic_complication) AS neurologic_complication_rate,
  AVG(CASE WHEN mortality_30d = 0 THEN los_hospital END) AS survivor_mean_los
FROM acs_final

UNION ALL

SELECT
  'Control Cohort' AS cohort_type,
  AVG(risk_score) AS mean_risk_score,
  AVG(mortality_30d) AS mortality_30d_rate,
  NULL AS cardiac_complication_rate,
  NULL AS neurologic_complication_rate,
  AVG(CASE WHEN mortality_30d = 0 THEN los_hospital END) AS survivor_mean_los
FROM control_final;