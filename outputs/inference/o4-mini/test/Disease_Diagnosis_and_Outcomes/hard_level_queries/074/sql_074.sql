WITH params AS (
  SELECT
    123456 AS target_subject_id,
    789012 AS target_hadm_id
),

pe_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.hospital_expire_flag IN (0,1)
    AND (
      d.icd_code LIKE 'I26%' 
      OR LOWER(dd.long_title) LIKE '%embolus%'
      OR LOWER(dd.long_title) LIKE '%emboli%'
    )
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.anchor_age, p.gender
),

comorbidity_counts AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    pe_cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
  WHERE
    NOT (d.icd_code LIKE 'I26%' OR LOWER(dd.long_title) LIKE '%embolus%')
  GROUP BY
    c.subject_id, c.hadm_id
),

quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS q3
  FROM
    comorbidity_counts
),

top_quartile_cohort AS (
  SELECT
    cc.subject_id,
    cc.hadm_id,
    cc.comorbidity_count
  FROM
    comorbidity_counts cc,
    quartile_cutoff qc
  WHERE
    cc.comorbidity_count >= qc.q3
),

risk_percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    PERCENT_RANK() OVER (ORDER BY comorbidity_count) AS risk_score_percentile
  FROM
    top_quartile_cohort
),

outcomes AS (
  SELECT
    COUNTIF(deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)) * 1.0 / COUNT(*) AS mortality_30d_rate,
    COUNTIF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
        WHERE d2.hadm_id = c.hadm_id
          AND d2.icd_code LIKE 'I21%'
      )
    ) * 1.0 / COUNT(*) AS cardiac_complication_rate,
    COUNTIF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d3
        WHERE d3.hadm_id = c.hadm_id
          AND (d3.icd_code BETWEEN 'I60' AND 'I69')
      )
    ) * 1.0 / COUNT(*) AS neurologic_complication_rate,
    APPROX_QUANTILES(
      DATE_DIFF(DATE(deathtime), DATE(admittime), DAY),
      2
    )[OFFSET(1)] AS median_survival_days
  FROM
    pe_cohort c
  JOIN
    top_quartile_cohort tq
    ON c.subject_id = tq.subject_id
   AND c.hadm_id    = tq.hadm_id
),

target_patient AS (
  SELECT
    rp.subject_id,
    rp.hadm_id,
    rp.risk_score_percentile
  FROM
    risk_percentiles rp
  JOIN
    params p
  ON rp.subject_id = p.target_subject_id
 AND rp.hadm_id    = p.target_hadm_id
)

SELECT
  tp.subject_id,
  tp.hadm_id,
  tp.risk_score_percentile,
  o.mortality_30d_rate,
  o.cardiac_complication_rate,
  o.neurologic_complication_rate,
  o.median_survival_days
FROM
  target_patient tp
CROSS JOIN
  outcomes o;