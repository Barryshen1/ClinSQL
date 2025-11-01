WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    a.hospital_expire_flag,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS calculated_age,
    NTILE(5) OVER (ORDER BY (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age)) AS quintile,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- 30-day mortality flag
    CASE 
      WHEN a.deathtime IS NOT NULL 
           AND a.deathtime <= TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY) THEN 1
      WHEN a.deathtime IS NULL 
           AND p.dod IS NOT NULL 
           AND DATE(p.dod) <= DATE_ADD(DATE(a.admittime), INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS mortality_30d,
    -- Cardiovascular complication flag (secondary diagnoses)
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = a.hadm_id 
          AND di.icd_version = 10
          AND di.seq_num > 1
          AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I50%')
      ) THEN 1 ELSE 0 
    END AS has_cardio,
    -- Neurologic complication flag (secondary diagnoses)
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = a.hadm_id 
          AND di.icd_version = 10
          AND di.seq_num > 1
          AND (di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'G40%' OR di.icd_code LIKE 'G41%')
      ) THEN 1 ELSE 0 
    END AS has_neuro
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
metrics AS (
  SELECT 
    quintile,
    COUNT(*) AS n_patients,
    SUM(mortality_30d) / COUNT(*) AS mortality_rate,
    SUM(has_cardio) / COUNT(*) AS cardio_rate,
    SUM(has_neuro) / COUNT(*) AS neuro_rate
  FROM cohort
  GROUP BY quintile
),
survivor_los AS (
  SELECT 
    quintile,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los
  FROM cohort
  WHERE mortality_30d = 0
  GROUP BY quintile
)
SELECT 
  m.quintile,
  m.n_patients,
  m.mortality_rate,
  m.cardio_rate,
  m.neuro_rate,
  s.median_los
FROM metrics m
LEFT JOIN survivor_los s 
  ON m.quintile = s.quintile
ORDER BY m.quintile;