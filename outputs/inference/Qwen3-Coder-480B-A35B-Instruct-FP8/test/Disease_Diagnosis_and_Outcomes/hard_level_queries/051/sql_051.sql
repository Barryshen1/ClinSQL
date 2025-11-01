WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
),

pancreatitis_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    c.los
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute pancreatitis%'
),

diagnosis_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

major_complications AS (
  SELECT
    d.hadm_id,
    COUNT(*) AS complication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) IN (
      'acute kidney failure',
      'sepsis',
      'respiratory failure',
      'shock'
    )
  GROUP BY
    d.hadm_id
),

risk_scores AS (
  SELECT
    pa.hadm_id,
    pa.hospital_expire_flag,
    pa.los,
    COALESCE(dc.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(mc.complication_count, 0) AS complication_count,
    COALESCE(dc.diagnosis_count, 0) + 5 * COALESCE(mc.complication_count, 0) AS risk_score
  FROM
    pancreatitis_admissions pa
  LEFT JOIN
    diagnosis_counts dc
  ON
    pa.hadm_id = dc.hadm_id
  LEFT JOIN
    major_complications mc
  ON
    pa.hadm_id = mc.hadm_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    risk_scores
)

SELECT
  risk_quartile,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(CASE WHEN complication_count > 0 THEN 1 ELSE 0 END) AS major_complication_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los
FROM
  quartiles
GROUP BY
  risk_quartile

UNION ALL

SELECT
  NULL AS risk_quartile,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(CASE WHEN complication_count > 0 THEN 1 ELSE 0 END) AS major_complication_rate,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los ELSE NULL END, 2)[OFFSET(1)] AS median_survivor_los
FROM
  quartiles

ORDER BY
  risk_quartile;