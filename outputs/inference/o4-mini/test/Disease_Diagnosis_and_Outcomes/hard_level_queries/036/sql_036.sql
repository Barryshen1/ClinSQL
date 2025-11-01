WITH pneumonia_dx AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
),
base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    p.dod
  FROM
    pneumonia_dx dx
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON dx.subject_id = a.subject_id
     AND dx.hadm_id    = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
comorbidity_counts AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    base_cohort bc
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON bc.subject_id = d.subject_id
     AND bc.hadm_id    = d.hadm_id
  GROUP BY
    d.subject_id,
    d.hadm_id
),
threshold AS (
  SELECT
    PERCENTILE_CONT(comorbidity_count, 0.75) OVER() AS comorbidity_75
  FROM
    comorbidity_counts
  LIMIT 1
),
filtered_cohort AS (
  SELECT
    bc.subject_id,
    bc.hadm_id,
    bc.anchor_age,
    bc.hospital_expire_flag,
    bc.admittime,
    bc.dischtime,
    bc.dod,
    cc.comorbidity_count
  FROM
    base_cohort bc
    JOIN comorbidity_counts cc
      ON bc.subject_id = cc.subject_id
     AND bc.hadm_id    = cc.hadm_id
    CROSS JOIN threshold t
  WHERE
    cc.comorbidity_count >= t.comorbidity_75
),
complication_codes AS (
  SELECT '51882' AS icd_code UNION ALL
  SELECT '51881' UNION ALL
  SELECT '99591' UNION ALL
  SELECT '99592'
),
complication_flags AS (
  SELECT
    fc.subject_id,
    fc.hadm_id,
    MAX(IF(cc.icd_code IS NOT NULL, 1, 0)) AS has_major_complication
  FROM
    filtered_cohort fc
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON fc.subject_id = d.subject_id
     AND fc.hadm_id    = d.hadm_id
    LEFT JOIN complication_codes cc
      ON d.icd_code = cc.icd_code
  GROUP BY
    fc.subject_id,
    fc.hadm_id
),
scored_cohort AS (
  SELECT
    fc.*,
    cf.has_major_complication,
    PERCENT_RANK() OVER (ORDER BY fc.comorbidity_count) AS composite_risk_percentile
  FROM
    filtered_cohort fc
    JOIN complication_flags cf
      ON fc.subject_id = cf.subject_id
     AND fc.hadm_id    = cf.hadm_id
),
cohort_metrics AS (
  SELECT
    ROUND(100 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_pct,
    ROUND(100 * AVG(has_major_complication), 2) AS major_complication_pct,
    CAST(
      APPROX_QUANTILES(
        DATE_DIFF(dod, dischtime, DAY),
        2
      )[OFFSET(1)] AS INT64
    ) AS median_survival_days
  FROM
    scored_cohort
),
target_patient AS (
  SELECT
    subject_id,
    hadm_id,
    composite_risk_percentile
  FROM
    scored_cohort
  WHERE
    subject_id = @target_subject_id
    AND hadm_id  = @target_hadm_id
)
SELECT
  tp.subject_id,
  tp.hadm_id,
  tp.composite_risk_percentile,
  cm.in_hospital_mortality_pct,
  cm.major_complication_pct,
  cm.median_survival_days
FROM
  target_patient tp
  CROSS JOIN cohort_metrics cm;