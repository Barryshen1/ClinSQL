WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    p.dod,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 82 AND 92
),
pneumonia_admissions AS (
  SELECT
    pa.*
  FROM
    patient_admissions pa
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        d.hadm_id = pa.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
),
admission_metrics AS (
  SELECT
    hadm_id,
    -- 30-day mortality
    CASE
      WHEN dod IS NOT NULL AND dod <= DATE_ADD(admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS died_within_30_days,
    -- Cardiovascular complication (ICD-10 I00-I99)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE
          d.hadm_id = pa.hadm_id
          AND dd.icd_version = 10
          AND dd.icd_code BETWEEN 'I00' AND 'I99'
      ) THEN 1
      ELSE 0
    END AS cardiovascular_complication,
    -- Neurologic complication (ICD-10 G00-G99)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE
          d.hadm_id = pa.hadm_id
          AND dd.icd_version = 10
          AND dd.icd_code BETWEEN 'G00' AND 'G99'
      ) THEN 1
      ELSE 0
    END AS neurologic_complication,
    -- LOS in days
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM
    pneumonia_admissions pa
),
admission_risk AS (
  SELECT
    hadm_id,
    died_within_30_days,
    cardiovascular_complication,
    neurologic_complication,
    los,
    RAND() AS composite_risk_score  -- Placeholder for actual risk score
  FROM
    admission_metrics
),
admission_quintiles AS (
  SELECT
    hadm_id,
    died_within_30_days,
    cardiovascular_complication,
    neurologic_complication,
    los,
    composite_risk_score,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS quintile
  FROM
    admission_risk
),
quintile_summary AS (
  SELECT
    quintile,
    AVG(died_within_30_days) AS mortality_rate,
    AVG(cardiovascular_complication) AS cardiovascular_complication_rate,
    AVG(neurologic_complication) AS neurologic_complication_rate,
    -- Median LOS for survivors only
    APPROX_QUANTILES(IF(died_within_30_days = 0, los, NULL), 2)[SAFE_OFFSET(1)] AS median_los
  FROM
    admission_quintiles
  GROUP BY
    quintile
)
SELECT
  quintile,
  mortality_rate,
  cardiovascular_complication_rate,
  neurologic_complication_rate,
  median_los
FROM
  quintile_summary
ORDER BY
  quintile;