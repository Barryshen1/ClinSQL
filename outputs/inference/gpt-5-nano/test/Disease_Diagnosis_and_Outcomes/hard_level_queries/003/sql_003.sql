WITH
-- 1) Define PE female 70-80 cohort (admissions that have a PE diagnosis)
pe_base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    a.admission_type,
    p.dod AS dod_date,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    -- Ensure the admission has a PE diagnosis (robust across ICD versions via long_title)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND dd.long_title LIKE '%Pulmonary embolism%'
    )
),

-- 2) AKI indicator per hadm_id
aki_map AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN (icd_version = 9 AND icd_code LIKE '584%')
                    OR (icd_version = 10 AND icd_code LIKE 'N17%')
               THEN 1 ELSE 0 END) AS aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- 3) ARDS indicator per hadm_id
ards_map AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN (icd_version = 9 AND icd_code LIKE '5185%')
                    OR (icd_version = 10 AND icd_code LIKE 'J80%')
               THEN 1 ELSE 0 END) AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- 4) Assemble risk components per admission
pe_risk AS (
  SELECT
    b.hadm_id,
    b.subject_id,
    b.admittime,
    b.dischtime,
    b.dod_date,
    b.anchor_age,
    b.admission_type,
    COALESCE(a.aki, 0) AS aki,
    COALESCE(m.ards, 0) AS ards,
    CASE WHEN b.anchor_age >= 75 THEN 1 ELSE 0 END AS age75plus,
    CASE WHEN b.admission_type IN ('EMERGENCY','URGENT') THEN 1 ELSE 0 END AS emergency_flag
  FROM pe_base AS b
  LEFT JOIN aki_map AS a ON b.hadm_id = a.hadm_id
  LEFT JOIN ards_map AS m ON b.hadm_id = m.hadm_id
),

-- 5) Compute risk_score and assign quintiles
risk AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    dod_date,
    anchor_age,
    aki,
    ards,
    age75plus,
    emergency_flag,
    (COALESCE(aki,0) + COALESCE(ards,0) + age75plus + emergency_flag) AS risk_score
  FROM pe_risk
),

risk_quint AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    dod_date,
    anchor_age,
    aki,
    ards,
    age75plus,
    emergency_flag,
    risk_score,
    NTILE(5) OVER (ORDER BY risk_score) AS quint
  FROM risk
)

-- 6) Per-quint metrics: 90-day mortality, AKI/ARDS rates, survivor LOS (median)
, quint_metrics AS (
  SELECT
    quint,
    COUNT(*) AS n_admissions,
    SUM(CASE
          WHEN dod_date IS NOT NULL
               AND DATE(dod_date) BETWEEN DATE(admittime) AND DATE(admittime) + INTERVAL 90 DAY
          THEN 1 ELSE 0 END) AS deaths_90d,
    SAFE_DIVIDE(
      SUM(CASE
            WHEN dod_date IS NOT NULL
                 AND DATE(dod_date) BETWEEN DATE(admittime) AND DATE(admittime) + INTERVAL 90 DAY
            THEN 1 ELSE 0 END),
      COUNT(*)
    ) AS mortality_90d_rate,
    SUM(aki) AS aki_in_quint,
    SUM(ards) AS ards_in_quint,
    AVG(age75plus) AS proportion_age75plus,
    AVG(emergency_flag) AS proportion_emergency,
    MEDIAN(
      CASE
        WHEN dod_date IS NULL OR DATE(dod_date) > DATE(admittime) + INTERVAL 90 DAY
        THEN TIMESTAMP_DIFF(dischtime, admittime, DAY)
        ELSE NULL
      END
    ) AS median_survivor_los_days
  FROM risk_quint
  GROUP BY quint
)

, -- 7) Overall 90-day mortality for female 70-80 (comparison)
overall_90d AS (
  SELECT SAFE_DIVIDE(
           SUM(CASE
                 WHEN p.dod IS NOT NULL
                      AND DATE(p.dod) BETWEEN DATE(a.admittime) AND DATE(a.admittime) + INTERVAL 90 DAY
                 THEN 1 ELSE 0 END),
           COUNT(*) 
         ) AS overall_90d_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 70 AND 80
)

-- 8) Final: combine quint metrics with the comparison value
SELECT
  qm.quint,
  qm.n_admissions,
  qm.deaths_90d,
  qm.mortality_90d_rate,
  qm.aki_in_quint,
  qm.ards_in_quint,
  qm.proportion_age75plus,
  qm.proportion_emergency,
  qm.median_survivor_los_days,
  o.overall_90d_mortality AS comparison_90d_mortality
FROM quint_metrics AS qm
CROSS JOIN overall_90d AS o
ORDER BY qm.quint;