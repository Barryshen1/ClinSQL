WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.dod,
    CASE
      WHEN p.dod IS NOT NULL
       AND DATE_DIFF(p.dod, a.dischtime, DAY) BETWEEN 0 AND 30
      THEN 1
      ELSE 0
    END AS mort_30d
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
dka_flag AS (
  SELECT
    b.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
          ON d.icd_code = dicd.icd_code
         AND d.icd_version = dicd.icd_version
        WHERE b.hadm_id = d.hadm_id
          AND (
            (d.icd_version = 10 AND LOWER(dicd.long_title) LIKE '%ketoacidosis%')
            OR (d.icd_version = 9 AND d.icd_code = '250.1')
          )
      ) THEN 1
      ELSE 0
    END AS is_dka
  FROM base b
),
complications AS (
  SELECT
    df.*,
    MAX(CASE
      WHEN (LEFT(d.icd_code, 3) BETWEEN 'I20' AND 'I25')
        OR (LEFT(d.icd_code, 3) BETWEEN 'I60' AND 'I69')
      THEN 1 ELSE 0 END) AS cv_comp,
    MAX(CASE
      WHEN LEFT(d.icd_code, 1) = 'G'
      THEN 1 ELSE 0 END) AS neuro_comp
  FROM dka_flag df
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON df.hadm_id = d.hadm_id
  GROUP BY
    df.subject_id, df.hadm_id, df.anchor_age, df.gender,
    df.admittime, df.dischtime, df.los_days, df.dod,
    df.mort_30d, df.is_dka
),
metrics AS (
  SELECT
    is_dka,
    COUNT(1) AS n_admissions,
    ROUND(100.0 * SUM(mort_30d) / COUNT(1), 2) AS mort_30d_pct,
    ROUND(100.0 * SUM(cv_comp) / COUNT(1), 2) AS cv_comp_pct,
    ROUND(100.0 * SUM(neuro_comp) / COUNT(1), 2) AS neuro_comp_pct,
    AVG(IF(mort_30d = 0, los_days, NULL)) AS mean_surv_los
  FROM complications
  GROUP BY is_dka
)
SELECT
  CASE WHEN is_dka = 1 THEN 'DKA' ELSE 'All male 39–49' END AS cohort,
  n_admissions,
  mort_30d_pct AS mortality_30d_pct,
  cv_comp_pct AS cardiovascular_complication_pct,
  neuro_comp_pct AS neurologic_complication_pct,
  mean_surv_los
FROM metrics
ORDER BY is_dka DESC;