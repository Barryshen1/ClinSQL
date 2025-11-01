WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    pat.dod,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    -- Age 59-69 at admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 59 AND 69
),
cardiac_arrest_diag AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '4275') OR  -- ICD-9 cardiac arrest
    (icd_version = 10 AND icd_code LIKE 'I46%') -- ICD-10 cardiac arrest
),
filtered_cohort AS (
  SELECT DISTINCT
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dod,
    c.los_days,
    c.age
  FROM cohort c
  INNER JOIN cardiac_arrest_diag cd
    ON c.hadm_id = cd.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
),
risk_score AS (
  SELECT 
    fc.hadm_id,
    COUNT(DISTINCT diag.icd_code) AS comorbidity_count
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON fc.hadm_id = diag.hadm_id
    -- Exclude cardiac arrest codes from comorbidity count
    AND NOT (
      (diag.icd_version = 9 AND diag.icd_code = '4275') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I46%')
    )
  GROUP BY fc.hadm_id
),
quartiles AS (
  SELECT 
    fc.*,
    rs.comorbidity_count,
    NTILE(4) OVER (ORDER BY rs.comorbidity_count) AS quartile
  FROM filtered_cohort fc
  INNER JOIN risk_score rs
    ON fc.hadm_id = rs.hadm_id
),
outcomes AS (
  SELECT 
    q.hadm_id,
    q.quartile,
    -- 30-day mortality flag
    CASE 
      WHEN q.dod IS NOT NULL AND q.dod <= DATETIME_ADD(q.admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- Cardiovascular complication flag (secondary diagnoses only)
    MAX(CASE 
      WHEN diag.seq_num > 1 AND (
        (diag.icd_version = 9 AND (
          diag.icd_code LIKE '410%' OR  -- MI
          diag.icd_code LIKE '428%' OR  -- HF
          (diag.icd_code >= '430' AND diag.icd_code < '439')  -- Stroke
        )) OR
        (diag.icd_version = 10 AND (
          diag.icd_code LIKE 'I21%' OR  -- MI
          diag.icd_code LIKE 'I22%' OR  -- MI
          diag.icd_code LIKE 'I50%' OR  -- HF
          diag.icd_code LIKE 'I6%'      -- Stroke
        ))
      ) THEN 1 ELSE 0 END
    ) AS cardiovascular_complication,
    -- Neurologic complication flag (secondary diagnoses only)
    MAX(CASE 
      WHEN diag.seq_num > 1 AND (
        (diag.icd_version = 9 AND (
          diag.icd_code = '3483' OR    -- Anoxic brain damage
          diag.icd_code = '78001' OR   -- Coma
          diag.icd_code LIKE '345%' OR -- Seizures
          diag.icd_code LIKE '7803%'   -- Seizures
        )) OR
        (diag.icd_version = 10 AND (
          diag.icd_code = 'G931' OR    -- Anoxic brain damage
          diag.icd_code = 'R402' OR    -- Coma
          diag.icd_code LIKE 'R56%'    -- Seizures
        ))
      ) THEN 1 ELSE 0 END
    ) AS neurologic_complication,
    -- LOS for survivors (exclude deaths)
    CASE 
      WHEN q.dod IS NULL OR q.dod > DATETIME_ADD(q.admittime, INTERVAL 30 DAY) 
        THEN q.los_days 
      ELSE NULL 
    END AS survivor_los
  FROM quartiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON q.hadm_id = diag.hadm_id
  GROUP BY q.hadm_id, q.quartile, q.admittime, q.dod, q.los_days
),
baseline_mortality AS (
  -- 30-day mortality for ALL female inpatients aged 59-69
  SELECT 
    'Baseline' AS quartile,
    COUNT(*) AS total_patients,
    AVG(CASE 
          WHEN pat.dod IS NOT NULL AND pat.dod <= DATETIME_ADD(adm.admittime, INTERVAL 30 DAY) THEN 1.0 
          ELSE 0 
        END) * 100 AS mortality_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 59 AND 69
),
quartile_summary AS (
  SELECT 
    CAST(quartile AS STRING) AS quartile,  -- Cast for consistent typing
    COUNT(*) AS patients_in_quartile,
    AVG(mortality_30d) * 100 AS mortality_30d_rate,
    AVG(cardiovascular_complication) * 100 AS cardiovascular_complication_rate,
    AVG(neurologic_complication) * 100 AS neurologic_complication_rate,
    -- Median LOS for survivors (using approximate median)
    APPROX_QUANTILES(survivor_los, 100 IGNORE NULLS)[OFFSET(50)] AS median_survivor_los
  FROM outcomes
  GROUP BY quartile
)
-- Final output: Quartiles + Baseline
SELECT 
  quartile,
  mortality_30d_rate,
  cardiovascular_complication_rate,
  neurologic_complication_rate,
  median_survivor_los
FROM quartile_summary

UNION ALL

SELECT 
  quartile,
  mortality_30d,
  NULL AS cardiovascular_complication_rate,  -- Not applicable
  NULL AS neurologic_complication_rate,     -- Not applicable
  NULL AS median_survivor_los               -- Not applicable
FROM baseline_mortality
ORDER BY quartile;