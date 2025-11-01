WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    DATETIME(p.anchor_year, 1, 1, 0, 0, 0) AS anchor_start
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'M'
),
admissions_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    pa.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pa.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_age pa ON a.subject_id = pa.subject_id
  WHERE (pa.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pa.anchor_year)) BETWEEN 39 AND 49
),
dka_codes AS (
  SELECT 'E101' AS icd_code UNION ALL
  SELECT 'E111' UNION ALL
  SELECT 'E131'
),
dka_flag AS (
  SELECT DISTINCT
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    aa.deathtime,
    aa.hospital_expire_flag,
    aa.age_at_admission,
    1 AS has_dka
  FROM admissions_age aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON aa.hadm_id = di.hadm_id
  INNER JOIN dka_codes dka ON di.icd_code = dka.icd_code AND di.icd_version = 10
),
all_admissions AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    aa.deathtime,
    aa.hospital_expire_flag,
    aa.age_at_admission,
    COALESCE(df.has_dka, 0) AS has_dka
  FROM admissions_age aa
  LEFT JOIN dka_flag df ON aa.hadm_id = df.hadm_id
),
-- Define complication ICD prefixes
cv_complication_codes AS (
  SELECT 'I21' AS prefix UNION ALL
  SELECT 'I22' UNION ALL
  SELECT 'I44' UNION ALL
  SELECT 'I45' UNION ALL
  SELECT 'I46' UNION ALL
  SELECT 'I47' UNION ALL
  SELECT 'I48' UNION ALL
  SELECT 'I49' UNION ALL
  SELECT 'I50'
),
neuro_complication_codes AS (
  SELECT 'I63' AS prefix UNION ALL
  SELECT 'G45' UNION ALL
  SELECT 'G46' UNION ALL
  SELECT 'R56' UNION ALL
  SELECT 'G40' UNION ALL
  SELECT 'F05' UNION ALL
  SELECT 'G934'
),
complication_flags AS (
  SELECT
    aa.hadm_id,
    MAX(CASE 
      WHEN EXISTS (
        SELECT 1 FROM cv_complication_codes cvc 
        WHERE STARTS_WITH(di.icd_code, cvc.prefix)
      ) THEN 1 ELSE 0 
    END) AS has_cv_complication,
    MAX(CASE 
      WHEN EXISTS (
        SELECT 1 FROM neuro_complication_codes nc 
        WHERE STARTS_WITH(di.icd_code, nc.prefix)
      ) THEN 1 ELSE 0 
    END) AS has_neuro_complication
  FROM all_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON aa.hadm_id = di.hadm_id AND di.icd_version = 10
  GROUP BY aa.hadm_id
),
admissions_with_comps AS (
  SELECT
    aa.*,
    COALESCE(cf.has_cv_complication, 0) AS has_cv_complication,
    COALESCE(cf.has_neuro_complication, 0) AS has_neuro_complication,
    -- 30-day mortality: died within 30 days of admission
    CASE 
      WHEN aa.deathtime IS NOT NULL 
       AND DATETIME_DIFF(aa.deathtime, aa.admittime, DAY) <= 30 
      THEN 1 ELSE 0 
    END AS thirty_day_mortality,
    -- Hospital LOS in days (for survivors only)
    CASE 
      WHEN aa.hospital_expire_flag = 0 
      THEN DATETIME_DIFF(aa.dischtime, aa.admittime, HOUR) / 24.0 
      ELSE NULL 
    END AS los_days_survivors
  FROM all_admissions aa
  LEFT JOIN complication_flags cf ON aa.hadm_id = cf.hadm_id
)
-- Final summary statistics
SELECT
  CASE WHEN has_dka = 1 THEN 'DKA' ELSE 'Non-DKA' END AS group_label,
  COUNT(*) AS n_admissions,
  AVG(thirty_day_mortality) AS mean_thirty_day_mortality,
  AVG(has_cv_complication) AS cv_complication_rate,
  AVG(has_neuro_complication) AS neuro_complication_rate,
  AVG(los_days_survivors) AS mean_los_survivors
FROM admissions_with_comps
GROUP BY has_dka
ORDER BY has_dka;