WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 44 AND 54
), DiagnosisInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    d.icd_code
  FROM
    PatientInfo AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I6%' -- Intracranial hemorrhage codes
), RiskScore AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    AVG(rs.drg_severity) AS avg_risk_score -- Using drg_severity as a proxy for risk score
  FROM
    DiagnosisInfo AS di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` AS rs
      ON di.subject_id = rs.subject_id AND di.hadm_id = rs.hadm_id
  GROUP BY
    di.subject_id,
    di.hadm_id
), Mortality AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM
    DiagnosisInfo AS di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
), Complication AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT c.seq_num) AS complication_count
  FROM
    DiagnosisInfo AS di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS c
      ON di.subject_id = c.subject_id AND di.hadm_id = c.hadm_id
  WHERE
    c.seq_num > 1 -- Major complications are usually listed after the primary diagnosis
  GROUP BY
    di.subject_id,
    di.hadm_id
), LOS AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    a.dischtime - a.admittime AS los
  FROM
    DiagnosisInfo AS di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
)
SELECT
  PERCENTILE_CONT(rs.avg_risk_score, 0.5) AS median_risk_score,
  PERCENTILE_CONT(rs.avg_risk_score, 0.25) AS lower_quartile_risk_score,
  PERCENTILE_CONT(rs.avg_risk_score, 0.75) AS upper_quartile_risk_score,
  AVG(m.mortality) AS mortality_rate,
  AVG(c.complication_count) AS complication_;