WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.dod,
    p.anchor_age,
    p.anchor_year,
    dr.drg_mortality,
    CAST(p.anchor_age AS INT64) + EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64) AS age,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE 
      WHEN p.dod IS NOT NULL 
        AND DATE(p.dod) <= DATE_ADD(DATE(a.admittime), INTERVAL 30 DAY) 
      THEN 1.0 
      ELSE 0.0 
    END AS mort_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dr 
    ON a.hadm_id = dr.hadm_id 
    AND dr.drg_type = 'APRDRG'
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age AS INT64) + EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64) BETWEEN 39 AND 49
    AND dr.drg_mortality IS NOT NULL
),
dka_cohort AS (
  SELECT *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = cohort.subject_id 
          AND di.hadm_id = cohort.hadm_id
          AND (
            (di.icd_version = 9 AND di.icd_code LIKE '2501%') OR
            (di.icd_version = 10 AND (
              di.icd_code LIKE 'E101%' OR 
              di.icd_code LIKE 'E111%' OR 
              di.icd_code LIKE 'E131%'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_dka
  FROM cohort
),
comp_cohort AS (
  SELECT *,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = dka_cohort.subject_id 
          AND di.hadm_id = dka_cohort.hadm_id
          AND (
            -- CV ICD-9
            (di.icd_version = 9 AND (
              di.icd_code LIKE '410%' OR 
              di.icd_code = '4111' OR 
              di.icd_code LIKE '427%' OR 
              di.icd_code LIKE '428%' OR 
              di.icd_code = '7855'
            )) OR
            -- CV ICD-10
            (di.icd_version = 10 AND (
              di.icd_code LIKE 'I21%' OR 
              di.icd_code LIKE 'I50%' OR 
              di.icd_code LIKE 'I47%' OR 
              di.icd_code = 'I48' OR 
              di.icd_code LIKE 'I49%' OR 
              di.icd_code = 'R570'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_cv,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.subject_id = dka_cohort.subject_id 
          AND di.hadm_id = dka_cohort.hadm_id
          AND (
            -- Neuro ICD-9
            (di.icd_version = 9 AND (
              di.icd_code LIKE '430%' OR 
              di.icd_code LIKE '431%' OR 
              di.icd_code LIKE '432%' OR 
              di.icd_code LIKE '433%' OR 
              di.icd_code LIKE '434%' OR 
              di.icd_code LIKE '435%' OR 
              di.icd_code = '436' OR 
              di.icd_code IN ('78001', '78009', '3483')
            )) OR
            -- Neuro ICD-10
            (di.icd_version = 10 AND (
              di.icd_code LIKE 'I63%' OR 
              di.icd_code = 'G459' OR 
              di.icd_code = 'R402' OR 
              di.icd_code = 'G934'
            ))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_neuro
  FROM dka_cohort
),
summary AS (
  SELECT 
    has_dka,
    COUNT(*) AS n_patients,
    AVG(drg_mortality) AS mean_risk_score,
    AVG(mort_30d) AS mean_30d_mortality,
    AVG(CAST(has_cv AS FLOAT64)) AS cv_comp_rate,
    AVG(CAST(has_neuro AS FLOAT64)) AS neuro_comp_rate,
    AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days END) AS mean_survivor_los
  FROM comp_cohort
  GROUP BY has_dka
),
mean_dka_risk AS (
  SELECT AVG(drg_mortality) AS dka_risk_score
  FROM comp_cohort 
  WHERE has_dka = 1
),
all_risk_dist AS (
  SELECT drg_mortality 
  FROM comp_cohort
)
SELECT 
  s.has_dka,
  s.n_patients,
  s.mean_risk_score,
  s.mean_30d_mortality,
  s.cv_comp_rate,
  s.neuro_comp_rate,
  s.mean_survivor_los,
  mdr.dka_risk_score,
  (SELECT 
     COUNTIF(drg_mortality <= mdr.dka_risk_score) * 100.0 / COUNT(*) 
   FROM all_risk_dist
  ) AS risk_percentile
FROM summary s
CROSS JOIN mean_dka_risk mdr;