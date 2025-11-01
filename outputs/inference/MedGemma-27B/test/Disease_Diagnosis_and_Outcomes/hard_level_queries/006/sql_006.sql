WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 70 AND 80
), AdmissionInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1 -- Assuming the primary diagnosis is the first one
    AND d.long_title LIKE '%lower GI bleeding%'
), RiskScore AS (
  SELECT
    hadm_id,
    -- Calculate a composite complication-based risk score here
    -- This is a placeholder, replace with actual risk score calculation
    -- Example: SUM(CASE WHEN itemid = 123 THEN value ELSE 0 END) AS risk_score
    -- For demonstration, we'll use a random score
    CAST(RAND() * 100 AS INT) AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    hadm_id IN (SELECT hadm_id FROM AdmissionInfo)
  GROUP BY
    hadm_id
), Quintiles AS (
  SELECT
    hadm_id,
    risk_score,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    RiskScore
), Mortality AS (
  SELECT
    a.hadm_id,
    CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = TRUE THEN 1 ELSE 0 END AS mortality_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.hadm_id IN (SELECT hadm_id FROM AdmissionInfo)
), Complication AS (
  SELECT
    hadm_id,
    -- Calculate a major complication rate here
    -- This is a placeholder, replace with actual complication calculation
    -- Example: COUNT(CASE WHEN itemid = 456 THEN 1 ELSE NULL END) AS complication_count
    -- For demonstration, we'll use a random complication count
    CAST(RAND() * 5 AS INT) AS complication_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedureevents`
  WHERE
    hadm_id IN (SELECT hadm_id FROM AdmissionInfo)
  GROUP BY
    hadm_id
), LOS AS (
  SELECT
    hadm_id,
    -- Calculate Length of Stay (LOS) here
    -- This is a placeholder, replace with actual LOS calculation
    -- Example: TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los
    -- For demonstration, we'll use a random LOS
    CAST(RAND() * 10 AS INT) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (SELECT hadm_id FROM AdmissionInfo)
)
SELECT
  q.risk_quintile,
  COUNT(DISTINCT q.hadm_id) AS N,
  AVG(m.mortality_flag) AS mortality_rate,
  AVG(c.complication_count) AS major_complication_rate,
  AVG(l.los) AS median_los_90_day_survivors
FROM
  Quintiles AS q
LEFT JOIN
  Mortality AS m ON q.hadm_id = m.had;