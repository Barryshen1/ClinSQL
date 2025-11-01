WITH
-- Base patient cohort: females 75-85
female_75_85 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

-- Admissions with COPD exacerbation
copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age,
    p.dod,
    -- Get primary diagnosis (lowest seq_num)
    FIRST_VALUE(d.icd_code) OVER (
      PARTITION BY a.subject_id, a.hadm_id
      ORDER BY di.seq_num
    ) AS primary_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    female_75_85 f ON a.subject_id = f.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    -- COPD exacerbation codes (J44.0, J44.1, J44.9)
    d.icd_code IN ('J440', 'J441', 'J449')
    AND di.icd_version = 10
),

-- Calculate composite risk score (simplified example)
risk_scores AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.los_days,
    -- Example score components (would be more comprehensive in practice)
    ca.anchor_age,
    -- Count of comorbidities (simplified)
    COUNT(DISTINCT di.icd_code) AS comorbidity_count,
    -- Lab values (example - would need proper joins)
    -- For this example, we'll use a placeholder score
    RAND() AS composite_score  -- Replace with actual score calculation
  FROM
    copd_admissions ca
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
  GROUP BY
    ca.subject_id, ca.hadm_id, ca.los_days, ca.anchor_age
),

-- Add quartile stratification
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY composite_score) AS risk_quartile
  FROM
    risk_scores
),

-- Calculate outcomes by quartile
quartile_outcomes AS (
  SELECT
    q.risk_quartile,
    -- 90-day mortality
    COUNT(CASE WHEN
      (ca.hospital_expire_flag = 1 OR
      (ca.deathtime IS NOT NULL AND TIMESTAMP_DIFF(ca.deathtime, ca.admittime, DAY) <= 90) OR
      (ca.dod IS NOT NULL AND TIMESTAMP_DIFF(ca.dod, ca.admittime, DAY) <= 90))
      THEN 1 END) AS mortality_90day,
    COUNT(*) AS total_patients,
    -- Major complications (simplified - would need proper definition)
    COUNT(DISTINCT CASE WHEN
      EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
          ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
        WHERE di.subject_id = q.subject_id AND di.hadm_id = q.hadm_id
          AND d.icd_code IN ('R6520', 'J189', 'N179')  -- Example complication codes
      )
      THEN q.subject_id END) AS major_complications,
    -- Median LOS for survivors
    APPROX_QUANTILES(CASE WHEN ca.hospital_expire_flag = 0 THEN ca.los_days END, 100)[OFFSET(50)] AS median_los_survivors
  FROM
    quartiles q
  JOIN
    copd_admissions ca ON q.subject_id = ca.subject_id AND q.hadm_id = ca.hadm_id
  GROUP BY
    q.risk_quartile
),

-- Broader 75-85 female mortality
broader_mortality AS (
  SELECT
    COUNT(CASE WHEN
      (a.hospital_expire_flag = 1 OR
      (a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 90) OR
      (p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 90))
      THEN 1 END) AS mortality_90day,
    COUNT(*) AS total_patients
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
)

-- Final results
SELECT
  q.risk_quartile,
  q.mortality_90day,
  ROUND(q.mortality_90day * 100.0 / q.total_patients, 2) AS mortality_90day_pct,
  q.major_complications,
  ROUND(q.major_complications * 100.0 / q.total_patients, 2) AS major_complications_pct,
  q.median_los_survivors,
  b.mortality_90day AS broader_mortality_90day,
  ROUND(b.mortality_90day * 100.0 / b.total_patients, 2) AS broader_mortality_90day_pct
FROM
  quartile_outcomes q
CROSS JOIN
  broader_mortality b
ORDER BY
  q.risk_quartile;