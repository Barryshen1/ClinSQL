WITH acs_cohort AS (
  -- ACS patients: female, 67-77, ICU stay, primary AMI (I21)
  SELECT 
    subject_id,
    gender,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    dod,
    -- Approximate age at admission using reconstructed DOB
    DATE_DIFF(DATE(admittime), DATE(anchor_year - anchor_age, 1, 1), YEAR) AS age,
    description AS drg_desc,
    drg_severity,
    -- Cardiac complication flag (secondary I20-I25)
    MAX(CASE WHEN seq_num > 1 AND icd_code LIKE 'I2[0-5]%' AND icd_version = '10' THEN 1 ELSE 0 END) AS has_cardiac_comp,
    -- Neurologic complication flag (secondary G45, I63, G93)
    MAX(CASE WHEN seq_num > 1 AND (icd_code LIKE 'G45%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'G93%') 
             AND icd_version = '10' THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM (
    SELECT DISTINCT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      p.anchor_year,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      p.dod,
      dc.description,
      dc.drg_severity,
      di.seq_num,
      di.icd_code,
      di.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id 
      AND di.icd_version = '10' 
      AND di.icd_code LIKE 'I21%'  -- Primary ACS (AMI)
      AND di.seq_num = 1
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
      AND icu.los >= 1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
      ON a.hadm_id = dc.hadm_id AND dc.drg_type = 'MS'
    WHERE p.gender = 'F'
      AND DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 67 AND 77
      AND p.anchor_year BETWEEN 2008 AND 2015  -- Anchor year range
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
  )
  GROUP BY subject_id, gender, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, 
           dod, age, drg_desc, drg_severity, anchor_year, anchor_age
),

general_cohort AS (
  -- General: female, 67-77, any inpatient (exclude ACS), at least one ICU stay
  SELECT 
    subject_id,
    gender,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag,
    dod,
    -- Approximate age at admission using reconstructed DOB
    DATE_DIFF(DATE(admittime), DATE(anchor_year - anchor_age, 1, 1), YEAR) AS age,
    description AS drg_desc,
    drg_severity,
    0 AS has_cardiac_comp,
    0 AS has_neuro_comp,
    anchor_year,
    anchor_age
  FROM (
    SELECT DISTINCT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      p.anchor_year,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      p.dod,
      dc.description,
      dc.drg_severity
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.subject_id = icu.subject_id AND a.hadm_id = icu.hadm_id
      AND icu.los >= 1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
      ON a.hadm_id = dc.hadm_id AND dc.drg_type = 'MS'
    WHERE p.gender = 'F'
      AND DATE_DIFF(DATE(a.admittime), DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 67 AND 77
      AND p.anchor_year BETWEEN 2008 AND 2015
      AND NOT EXISTS (
        SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2 
        WHERE di2.hadm_id = a.hadm_id 
          AND di2.icd_version = '10' 
          AND di2.icd_code LIKE 'I21%' 
          AND di2.seq_num = 1
      )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
  )
),

combined_cohort AS (
  SELECT 'ACS' AS cohort, * FROM acs_cohort
  UNION ALL
  SELECT 'General' AS cohort, * FROM general_cohort
),

mortality_los AS (
  SELECT 
    cohort,
    COUNT(*) AS n_patients,
    AVG(COALESCE(CAST(drg_severity AS NUMERIC), 0)) AS mean_risk_score,
    -- 30-day mortality
    SUM(CASE WHEN CAST(hospital_expire_flag AS INT64) = 1 
             OR (dod IS NOT NULL AND DATE(dod) <= DATE_ADD(DATE(admittime), INTERVAL 30 DAY))
             THEN 1 ELSE 0 END) AS n_30d_deaths,
    -- Survivor hospital LOS (days)
    AVG(CASE WHEN CAST(hospital_expire_flag AS INT64) = 0 
             THEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) ELSE NULL END) AS mean_los_survivors
  FROM combined_cohort
  GROUP BY cohort
),

complications AS (
  SELECT 
    'ACS' AS cohort,
    AVG(has_cardiac_comp) AS cardiac_comp_rate,
    AVG(has_neuro_comp) AS neuro_comp_rate
  FROM acs_cohort
),

-- Compute median LOS for survivors by cohort
median_los AS (
  SELECT 
    cohort,
    PERCENTILE_CONT(0.5) OVER (ORDER BY survivor_los) AS median_survivor_los
  FROM (
    SELECT 
      cohort,
      DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS survivor_los
    FROM combined_cohort
    WHERE CAST(hospital_expire_flag AS INT64) = 0
  )
  GROUP BY cohort
),

-- Compute LOS percentile: rank ACS median within general survivor LOS distribution
los_percentile AS (
  SELECT 
    ml.cohort,
    CASE 
      WHEN ml.cohort = 'ACS' THEN 
        (COUNTIF(g.survivor_los <= ml.median_survivor_los) * 1.0 / COUNT(*)) * 100 
      ELSE 0 
    END AS matched_profile_los_percentile
  FROM median_los ml
  CROSS JOIN (
    SELECT DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS survivor_los
    FROM combined_cohort
    WHERE cohort = 'General' AND CAST(hospital_expire_flag AS INT64) = 0
  ) g
  WHERE ml.cohort = 'ACS'
  GROUP BY ml.cohort, ml.median_survivor_los
  UNION ALL
  SELECT 'General' AS cohort, 0 AS matched_profile_los_percentile
)

SELECT 
  ml.cohort,
  ml.mean_risk_score,
  (ml.n_30d_deaths * 1.0 / ml.n_patients) AS mortality_30d_rate,
  ml.mean_los_survivors,
  COALESCE(c.cardiac_comp_rate, 0) AS cardiac_comp_rate,
  COALESCE(c.neuro_comp_rate, 0) AS neuro_comp_rate,
  COALESCE(lp.matched_profile_los_percentile, 0) AS matched_profile_los_percentile
FROM mortality_los ml
LEFT JOIN complications c ON ml.cohort = c.cohort
LEFT JOIN los_percentile lp ON ml.cohort = lp.cohort
ORDER BY CASE WHEN ml.cohort = 'ACS' THEN 1 ELSE 2 END;