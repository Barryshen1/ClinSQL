WITH pneumonia_admissions AS (
  -- Select female inpatients aged 82-92 with pneumonia
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      -- ICD-10 pneumonia: J12-J18
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
      -- ICD-9 pneumonia: 480-486
      OR (d.icd_version = 9 AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486)
    )
),

comorbidity_counts AS (
  -- Count distinct comorbidities per admission (excluding pneumonia codes)
  SELECT
    d.hadm_id,
    COUNT(DISTINCT CASE
      -- Example: chronic diseases for Charlson-like index
      WHEN (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I1[0-5]') -- Hypertension, heart disease
        OR REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]') -- Diabetes
        OR REGEXP_CONTAINS(d.icd_code, r'^C') -- Cancer
        OR REGEXP_CONTAINS(d.icd_code, r'^N1[8-9]') -- CKD
        OR REGEXP_CONTAINS(d.icd_code, r'^J4[4-7]') -- COPD
      ))
      OR (d.icd_version = 9 AND (
        SAFE_CAST(d.icd_code AS INT64) BETWEEN 390 AND 459 -- Heart
        OR SAFE_CAST(d.icd_code AS INT64) BETWEEN 250 AND 259 -- Diabetes
        OR SAFE_CAST(d.icd_code AS INT64) BETWEEN 140 AND 239 -- Cancer
        OR SAFE_CAST(d.icd_code AS INT64) BETWEEN 585 AND 586 -- CKD
        OR SAFE_CAST(d.icd_code AS INT64) BETWEEN 490 AND 496 -- COPD
      ))
      THEN d.icd_code
      ELSE NULL
    END) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    d.hadm_id
),

risk_scores AS (
  -- Composite risk score: age + hospital_expire_flag + comorbidity_count
  SELECT
    pa.*,
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
    CAST(pa.anchor_age AS FLOAT64)
      + CAST(pa.hospital_expire_flag AS FLOAT64)
      + COALESCE(cc.comorbidity_count, 0) AS risk_score
  FROM
    pneumonia_admissions pa
    LEFT JOIN comorbidity_counts cc
      ON pa.hadm_id = cc.hadm_id
),

quintiles AS (
  -- Assign quintiles based on risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    risk_scores
),

complications AS (
  -- Identify cardiovascular and neurologic complications per admission
  SELECT
    q.hadm_id,
    MAX(CASE
      -- Cardiovascular: ICD-10 I21-I22, I50, I48, I63-I64; ICD-9 410-411, 428, 427, 434-436
      WHEN (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I2[1-2]') -- MI
        OR d.icd_code = 'I50' -- Heart failure
        OR d.icd_code = 'I48' -- AFib
        OR REGEXP_CONTAINS(d.icd_code, r'^I6[3-4]') -- Stroke
      ))
      OR (d.icd_version = 9 AND (
        SAFE_CAST(d.icd_code AS INT64) BETWEEN 410 AND 411 -- MI
        OR SAFE_CAST(d.icd_code AS INT64) = 428 -- Heart failure
        OR SAFE_CAST(d.icd_code AS INT64) = 427 -- Arrhythmia
        OR SAFE_CAST(d.icd_code AS INT64) BETWEEN 434 AND 436 -- Stroke
      ))
      THEN 1 ELSE 0 END) AS cv_complication,
    MAX(CASE
      -- Neurologic: ICD-10 I60-I69, G40, F05; ICD-9 430-438, 345, 293
      WHEN (d.icd_version = 10 AND (
        REGEXP_CONTAINS(d.icd_code, r'^I6[0-9]') -- Stroke
        OR d.icd_code = 'G40' -- Seizure
        OR d.icd_code = 'F05' -- Delirium
      ))
      OR (d.icd_version = 9 AND (
        SAFE_CAST(d.icd_code AS INT64) BETWEEN 430 AND 438 -- Stroke
        OR SAFE_CAST(d.icd_code AS INT64) = 345 -- Seizure
        OR SAFE_CAST(d.icd_code AS INT64) = 293 -- Delirium
      ))
      THEN 1 ELSE 0 END) AS neuro_complication
  FROM
    quintiles q
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON q.hadm_id = d.hadm_id
  GROUP BY
    q.hadm_id
),

final AS (
  -- Merge all info
  SELECT
    q.subject_id,
    q.hadm_id,
    q.admittime,
    q.dischtime,
    q.deathtime,
    q.dod,
    q.hospital_expire_flag,
    q.anchor_age,
    q.risk_score,
    q.risk_quintile,
    c.cv_complication,
    c.neuro_complication,
    -- Calculate LOS
    DATETIME_DIFF(q.dischtime, q.admittime, DAY) AS los,
    -- 30-day mortality: died in hospital within 30 days, or died after discharge within 30 days
    CASE
      WHEN q.deathtime IS NOT NULL AND DATETIME_DIFF(q.deathtime, q.admittime, DAY) <= 30 THEN 1
      WHEN q.dod IS NOT NULL AND DATETIME_DIFF(q.dod, q.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Survivor flag: did not die in hospital
    CASE WHEN q.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS survivor
  FROM
    quintiles q
    LEFT JOIN complications c
      ON q.hadm_id = c.hadm_id
)

-- Aggregate by quintile
SELECT
  risk_quintile,
  COUNT(*) AS n_admissions,
  ROUND(SUM(mortality_30d) / COUNT(*), 3) AS mortality_30d_rate,
  ROUND(SUM(cv_complication) / COUNT(*), 3) AS cv_complication_rate,
  ROUND(SUM(neuro_complication) / COUNT(*), 3) AS neuro_complication_rate,
  -- Median LOS among survivors
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_survivors
FROM
  final
WHERE
  survivor = 1 -- For LOS median, only survivors
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;