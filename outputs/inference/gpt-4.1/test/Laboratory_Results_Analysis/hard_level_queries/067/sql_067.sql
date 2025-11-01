WITH acs_icd_codes AS (
  -- Get ICD codes for ACS (ICD-9: 410-414, ICD-10: I20-I25)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^41[0-4]'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I2[0-5]'))
),
acs_admissions AS (
  -- Female, age 53-63, with ACS diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN acs_icd_codes acs
    ON dx.icd_code = acs.icd_code AND dx.icd_version = acs.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),
control_admissions AS (
  -- Female, age 53-63, WITHOUT ACS diagnosis
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
    AND adm.hadm_id NOT IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN acs_icd_codes acs
        ON dx.icd_code = acs.icd_code AND dx.icd_version = acs.icd_version
    )
),
critical_lab_categories AS (
  -- For each admission, count unique critical lab categories in first 72h
  SELECT
    le.hadm_id,
    COUNT(DISTINCT dlab.category) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  JOIN acs_admissions adm
    ON le.hadm_id = adm.hadm_id
  WHERE
    TIMESTAMP_DIFF(le.charttime, adm.admittime, HOUR) BETWEEN 0 AND 72
    AND (LOWER(le.flag) LIKE '%critical%' OR LOWER(le.flag) LIKE '%abnormal%')
  GROUP BY le.hadm_id
),
acs_lab_scores AS (
  -- Merge instability scores with ACS admissions (score=0 if no critical labs)
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    IFNULL(clc.instability_score, 0) AS instability_score
  FROM acs_admissions adm
  LEFT JOIN critical_lab_categories clc
    ON adm.hadm_id = clc.hadm_id
),
acs_quartiles AS (
  -- Assign quartiles based on instability score
  SELECT *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM acs_lab_scores
),
acs_summary AS (
  -- Aggregate mortality and LOS by quartile
  SELECT
    instability_quartile,
    COUNT(*) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_percent,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0), 2) AS avg_los_days,
    ROUND(AVG(instability_score), 2) AS avg_instability_score
  FROM acs_quartiles
  GROUP BY instability_quartile
  ORDER BY instability_quartile
),
control_lab_categories AS (
  -- For controls: count unique critical lab categories in first 72h
  SELECT
    le.hadm_id,
    COUNT(DISTINCT dlab.category) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  JOIN control_admissions adm
    ON le.hadm_id = adm.hadm_id
  WHERE
    TIMESTAMP_DIFF(le.charttime, adm.admittime, HOUR) BETWEEN 0 AND 72
    AND (LOWER(le.flag) LIKE '%critical%' OR LOWER(le.flag) LIKE '%abnormal%')
  GROUP BY le.hadm_id
),
control_lab_scores AS (
  -- Merge instability scores with control admissions (score=0 if no critical labs)
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    IFNULL(clc.instability_score, 0) AS instability_score
  FROM control_admissions adm
  LEFT JOIN control_lab_categories clc
    ON adm.hadm_id = clc.hadm_id
),
control_quartiles AS (
  -- Assign quartiles for controls
  SELECT *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM control_lab_scores
),
control_summary AS (
  -- Aggregate for controls
  SELECT
    instability_quartile,
    COUNT(*) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_percent,
    ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0), 2) AS avg_los_days,
    ROUND(AVG(instability_score), 2) AS avg_instability_score
  FROM control_quartiles
  GROUP BY instability_quartile
  ORDER BY instability_quartile
)

-- Final output: ACS and controls summary side by side
SELECT
  'ACS' AS cohort,
  instability_quartile,
  n_admissions,
  n_deaths,
  mortality_percent,
  avg_los_days,
  avg_instability_score
FROM acs_summary

UNION ALL

SELECT
  'Control' AS cohort,
  instability_quartile,
  n_admissions,
  n_deaths,
  mortality_percent,
  avg_los_days,
  avg_instability_score
FROM control_summary
ORDER BY cohort, instability_quartile;