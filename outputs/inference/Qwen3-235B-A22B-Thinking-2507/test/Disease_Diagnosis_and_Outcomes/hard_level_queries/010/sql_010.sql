WITH base AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 39 AND 49
),
dka_flag AS (
  SELECT
    hadm_id,
    MAX(CASE
          WHEN icd_version = 10
            AND (icd_code LIKE 'E08.1%' 
                 OR icd_code LIKE 'E09.1%' 
                 OR icd_code LIKE 'E10.1%' 
                 OR icd_code LIKE 'E11.1%' 
                 OR icd_code LIKE 'E13.1%')
          THEN 1 ELSE 0
        END) AS has_dka
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
complications AS (
  SELECT
    hadm_id,
    MAX(CASE
          WHEN icd_version = 10 AND icd_code >= 'I00' AND icd_code < 'J00'
          THEN 1 ELSE 0
        END) AS has_cv_complication,
    MAX(CASE
          WHEN icd_version = 10 AND icd_code >= 'G00' AND icd_code < 'H00'
          THEN 1 ELSE 0
        END) AS has_neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
combined AS (
  SELECT
    b.hadm_id,
    b.hospital_expire_flag,
    COALESCE(df.has_dka, 0) AS has_dka,
    COALESCE(c.has_cv_complication, 0) AS has_cv_complication,
    COALESCE(c.has_neuro_complication, 0) AS has_neuro_complication,
    CASE
      WHEN b.dod IS NOT NULL AND datetime_diff(b.dod, b.admittime, DAY) <= 30
      THEN 1 ELSE 0
    END AS died_30d,
    datetime_diff(b.dischtime, b.admittime, HOUR) / 24.0 AS los
  FROM base b
  LEFT JOIN dka_flag df ON b.hadm_id = df.hadm_id
  LEFT JOIN complications c ON b.hadm_id = c.hadm_id
)
SELECT
  'DKA' AS group_name,
  COUNT(*) AS n,
  AVG(died_30d) AS mortality_30d,
  AVG(has_cv_complication) AS cv_complication_rate,
  AVG(has_neuro_complication) AS neuro_complication_rate,
  AVG(CASE WHEN hospital_expire_flag = 0 THEN los END) AS mean_survivor_los
FROM combined
WHERE has_dka = 1

UNION ALL

SELECT
  'All males' AS group_name,
  COUNT(*) AS n,
  AVG(died_30d) AS mortality_30d,
  AVG(has_cv_complication) AS cv_complication_rate,
  AVG(has_neuro_complication) AS neuro_complication_rate,
  AVG(CASE WHEN hospital_expire_flag = 0 THEN los END) AS mean_survivor_los
FROM combined;