WITH
-- 1. Get admissions for female, age 71-81, with complications of care
complication_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    -- Complications of care ICD codes (ICD-9: 996-999, E870-E879; ICD-10: T80-T88)
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 71 AND 81
      AND (
        (d.icd_version = 9 AND (
          SAFE_CAST(d.icd_code AS INT64) BETWEEN 996 AND 999
          OR d.icd_code BETWEEN 'E870' AND 'E879'
        ))
        OR
        (d.icd_version = 10 AND (
          d.icd_code BETWEEN 'T80' AND 'T88'
        ))
      )
),

-- 2. Mark ICU admissions
icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

admissions_with_icu_flag AS (
  SELECT
    ca.*,
    CASE WHEN ia.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM
    complication_admissions ca
    LEFT JOIN icu_admissions ia
      ON ca.hadm_id = ia.hadm_id
),

-- 3. Compute LOS quartiles over the cohort
los_stats AS (
  SELECT
    -- APPROX_QUANTILES returns [min, Q1, Q2, Q3, max]
    APPROX_QUANTILES(los_days, 4) AS los_quartiles
  FROM admissions_with_icu_flag
),

los_quartile_bounds AS (
  SELECT
    los_quartiles[OFFSET(1)] AS q1,
    los_quartiles[OFFSET(2)] AS q2,
    los_quartiles[OFFSET(3)] AS q3
  FROM los_stats
),

-- 4. Assign LOS quartile to each admission
admissions_with_los_quartile AS (
  SELECT
    a.*,
    CASE
      WHEN a.los_days < b.q1 THEN 'Q1'
      WHEN a.los_days < b.q2 THEN 'Q2'
      WHEN a.los_days < b.q3 THEN 'Q3'
      ELSE 'Q4'
    END AS los_quartile
  FROM
    admissions_with_icu_flag a
    CROSS JOIN los_quartile_bounds b
),

-- 5. Flag interventions per admission
interventions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Mechanical ventilation
    CASE
      WHEN icu.is_icu = 1 THEN
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
          WHERE pe.hadm_id = a.hadm_id
            AND pe.itemid IN (225792, 225794, 225790, 224687) -- Example: "Mechanical Ventilation", "Ventilator Mode", "Endotracheal Tube", "ETT"
        )
      ELSE
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
          WHERE pi.hadm_id = a.hadm_id
            AND (
              (pi.icd_version = 9 AND pi.icd_code LIKE '96.7%') -- ICD-9: 96.70, 96.71, 96.72
            )
        )
    END AS has_ventilation,

    -- Vasopressors
    CASE
      WHEN icu.is_icu = 1 THEN
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
          WHERE ie.hadm_id = a.hadm_id
            AND ie.itemid IN (221906, 221289, 221662, 221653, 221749) -- Example: norepinephrine, epinephrine, vasopressin, dopamine, phenylephrine
        )
      ELSE
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
          WHERE pr.hadm_id = a.hadm_id
            AND LOWER(pr.drug) IN ('norepinephrine', 'epinephrine', 'vasopressin', 'dopamine', 'phenylephrine')
        )
    END AS has_vasopressor,

    -- RRT
    CASE
      WHEN icu.is_icu = 1 THEN
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
          WHERE pe.hadm_id = a.hadm_id
            AND pe.itemid IN (227558, 225810, 225811) -- Example: "CRRT", "Hemodialysis"
        )
      ELSE
        EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
          WHERE pi.hadm_id = a.hadm_id
            AND (
              (pi.icd_version = 9 AND pi.icd_code IN ('39.95', '54.98')) -- Hemodialysis, Peritoneal dialysis
            )
        )
    END AS has_rrt
  FROM
    admissions_with_los_quartile a
    LEFT JOIN (
      SELECT hadm_id, MAX(is_icu) AS is_icu
      FROM admissions_with_los_quartile
      GROUP BY hadm_id
    ) icu
      ON a.hadm_id = icu.hadm_id
),

-- 6. Combine all info
final AS (
  SELECT
    a.hadm_id,
    a.is_icu,
    a.los_quartile,
    a.hospital_expire_flag,
    i.has_ventilation,
    i.has_vasopressor,
    i.has_rrt
  FROM
    admissions_with_los_quartile a
    LEFT JOIN interventions i
      ON a.hadm_id = i.hadm_id
),

-- 6b. Add group_type as a real column for window functions
final_with_group AS (
  SELECT
    *,
    CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS group_type
  FROM final
)

-- 7. Aggregate by ICU status and LOS quartile
SELECT
  group_type,
  los_quartile,
  COUNT(*) AS n_admissions,
  SUM(hospital_expire_flag) AS n_deaths,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
  ROUND(100 * SUM(CASE WHEN has_ventilation THEN 1 ELSE 0 END) / COUNT(*), 1) AS ventilation_pct,
  ROUND(100 * SUM(CASE WHEN has_vasopressor THEN 1 ELSE 0 END) / COUNT(*), 1) AS vasopressor_pct,
  ROUND(100 * SUM(CASE WHEN has_rrt THEN 1 ELSE 0 END) / COUNT(*), 1) AS rrt_pct,
  -- For absolute/relative mortality vs Q1, use window functions
  FIRST_VALUE(ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1)) OVER (PARTITION BY group_type ORDER BY los_quartile) AS q1_mortality_pct,
  ROUND( (ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1)) - 
         FIRST_VALUE(ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1)) OVER (PARTITION BY group_type ORDER BY los_quartile), 1) AS abs_mortality_vs_q1,
  ROUND( (ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1)) / 
         NULLIF(FIRST_VALUE(ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 1)) OVER (PARTITION BY group_type ORDER BY los_quartile), 0), 2) AS rel_mortality_vs_q1
FROM
  final_with_group
GROUP BY
  group_type, los_quartile
ORDER BY
  group_type, los_quartile;