WITH pneumonia_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON a.subject_id = icu.subject_id
     AND a.hadm_id    = icu.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON a.subject_id = dx.subject_id
     AND a.hadm_id    = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dxd
      ON dx.icd_code    = dxd.icd_code
     AND dx.icd_version = dxd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dxd.long_title) LIKE '%pneumonia%'
),
stats AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS cohort_size,
    -- In-hospital mortality
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    -- AKI indicator per admission
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dx2
        ON d2.icd_code    = dx2.icd_code
       AND d2.icd_version = dx2.icd_version
      WHERE d2.hadm_id = pc.hadm_id
        AND LOWER(dx2.long_title) LIKE '%acute kidney injury%'
    ) THEN 1 ELSE 0 END) AS aki_count,
    -- ARDS indicator per admission
    SUM(CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d3
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dx3
        ON d3.icd_code    = dx3.icd_code
       AND d3.icd_version = dx3.icd_version
      WHERE d3.hadm_id = pc.hadm_id
        AND LOWER(dx3.long_title) LIKE '%acute respiratory distress syndrome%'
    ) THEN 1 ELSE 0 END) AS ards_count,
    -- Median survival days among decedents
    APPROX_QUANTILES(
      DATE_DIFF(DATE(deathtime), DATE(admittime), DAY),
      2
    )[OFFSET(1)] AS median_survival_days
  FROM
    pneumonia_cohort AS pc
),
final AS (
  SELECT
    cohort_size,
    deaths,
    ROUND(deaths / cohort_size * 100, 1)   AS mortality_pct,
    aki_count,
    ROUND(aki_count / cohort_size * 100, 1) AS aki_pct,
    ards_count,
    ROUND(ards_count / cohort_size * 100, 1) AS ards_pct,
    median_survival_days
  FROM
    stats
)
SELECT * FROM final;