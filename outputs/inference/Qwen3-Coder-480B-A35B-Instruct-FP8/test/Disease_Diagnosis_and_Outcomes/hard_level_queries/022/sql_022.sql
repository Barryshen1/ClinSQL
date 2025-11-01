WITH aki_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.dod,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute kidney injury%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Comorbidities
comorbidities AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CASE
      WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN d.icd_code
      WHEN LOWER(dd.long_title) LIKE '%hypertension%' THEN d.icd_code
      WHEN LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN d.icd_code
      WHEN LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary%' THEN d.icd_code
      WHEN LOWER(dd.long_title) LIKE '%myocardial infarction%' THEN d.icd_code
    END) AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM aki_patients)
  GROUP BY
    hadm_id
),

-- ARDS flag
ards_flag AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%ards%' THEN 1 ELSE 0 END) AS has_ards
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.hadm_id IN (SELECT hadm_id FROM aki_patients)
  GROUP BY
    hadm_id
),

-- Composite risk score
risk_score AS (
  SELECT
    a.hadm_id,
    a.dischtime,
    a.los,
    a.dod,
    COALESCE(c.comorbidity_count, 0) AS comorbidities,
    COALESCE(ar.has_ards, 0) AS ards,
    (5 * COALESCE(c.comorbidity_count, 0)) + (50 * COALESCE(ar.has_ards, 0)) AS risk_score
  FROM
    aki_patients a
  LEFT JOIN
    comorbidities c ON a.hadm_id = c.hadm_id
  LEFT JOIN
    ards_flag ar ON a.hadm_id = ar.hadm_id
),

-- Quintiles
quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score.risk_score) AS risk_quintile
  FROM
    risk_score
),

-- Outcomes
outcomes AS (
  SELECT
    risk_quintile,
    COUNT(*) AS n,
    AVG(CASE
      WHEN dod IS NOT NULL AND dod <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END) * 100 AS mortality_30d_pct,
    AVG(ards) * 100 AS ards_pct,
    APPROX_QUANTILES(
      CASE
        WHEN dod IS NULL OR dod > DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN los
        ELSE NULL
      END, 2)[OFFSET(1)] AS median_survivor_los
  FROM
    quintiles
  GROUP BY
    risk_quintile
)

SELECT
  risk_quintile,
  n,
  ROUND(mortality_30d_pct, 2) AS mortality_30d_pct,
  ROUND(ards_pct, 2) AS ards_pct,
  median_survivor_los
FROM
  outcomes
ORDER BY
  risk_quintile;