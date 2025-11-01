WITH acute_pancreatitis_adm AS (
  -- Step 1: Identify admissions for male patients age 35-45 with acute pancreatitis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
     AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND LOWER(dd.long_title) LIKE '%pancreatitis%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),
diag_and_comp AS (
  -- Step 2: For each hadm_id compute diagnosis count and major complication flag
  SELECT
    d.subject_id,
    d.hadm_id,
    COUNT(*) AS total_diag_count,
    MAX(CASE
      WHEN d.icd_code IN ('5849','51881','99592','78552') THEN 1
      ELSE 0
    END) AS major_comp_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN acute_pancreatitis_adm AS a
      ON d.subject_id = a.subject_id
     AND d.hadm_id    = a.hadm_id
  GROUP BY
    d.subject_id,
    d.hadm_id
),
scores AS (
  -- Step 3 & 4: Compute risk score and assign quartiles
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    dac.total_diag_count,
    dac.major_comp_flag,
    (dac.total_diag_count + 5 * dac.major_comp_flag) AS risk_score,
    NTILE(4) OVER (ORDER BY (dac.total_diag_count + 5 * dac.major_comp_flag)) AS risk_quartile
  FROM
    acute_pancreatitis_adm AS a
    JOIN diag_and_comp AS dac
      ON a.subject_id = dac.subject_id
     AND a.hadm_id    = dac.hadm_id
),
quartile_stats AS (
  -- Step 5: Compute metrics by quartile among survivors
  SELECT
    CAST(risk_quartile AS STRING) AS risk_quartile,
    COUNT(*) AS n_admissions,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    AVG(CAST(major_comp_flag    AS FLOAT64)) AS major_complication_rate,
    APPROX_QUANTILES(
      TIMESTAMP_DIFF(dischtime, admittime, DAY), 
      2
    )[OFFSET(1)] AS median;