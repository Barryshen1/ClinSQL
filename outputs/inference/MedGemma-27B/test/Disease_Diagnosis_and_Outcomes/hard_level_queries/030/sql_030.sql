WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 64 AND 74
), Diagnosis AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(d.icd_code) AS diagnosis_count
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  GROUP BY
    p.subject_id,
    p.hadm_id
), Complication AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(CASE WHEN c.seq_num = 1 THEN c.icd_code ELSE NULL END) AS major_complication_count
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS c
      ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE
    c.icd_code LIKE 'I10%' -- Upper GI bleeding
  GROUP BY
    p.subject_id,
    p.hadm_id
), RiskScore AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.diagnosis_count + 20 * c.major_complication_count AS composite_risk_score
  FROM
    Diagnosis AS d
    INNER JOIN Complication AS c
      ON d.subject_id = c.subject_id AND d.hadm_id = c.hadm_id
), Quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    composite_risk_score,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM
    RiskScore
), Mortality AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quintile,
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM
    Quintiles AS q
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
), ComplicationRate AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quintile,
    CASE WHEN c.major_complication_count > 0 THEN 1 ELSE 0 END AS major_complication
  FROM
    Quintiles AS q
    INNER JOIN Complication AS c
      ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id
), LOS AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.risk_quintile,
    a.los
  FROM
    Quintiles AS q
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
), Final AS (
  SELECT
    q.risk_quintile,
    COUNT(DISTINCT q.subject_id) AS n,
    AVG(rs.composite_risk_score) AS mean_score,
    AVG(m.mortality) AS mortality_percent,
    AVG(cr.major_complication) AS complication_percent,
    MEDIAN(l.los) AS median_los_survivors
  FROM
    Quintiles AS q
    INNER JOIN RiskScore AS rs
      ON q.subject_id = rs.subject_id AND q.hadm_id = rs.hadm_id
    INNER JOIN Mortality AS m
      ON q.subject_;