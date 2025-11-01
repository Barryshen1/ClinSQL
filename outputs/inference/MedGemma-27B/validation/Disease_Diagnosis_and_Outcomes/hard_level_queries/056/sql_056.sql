WITH PatientProfile AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    COUNT(DISTINCT di.icd_code) AS num_diagnoses
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
  GROUP BY
    p.subject_id,
    p.gender,
    p.anchor_age
  HAVING
    COUNT(DISTINCT di.icd_code) > 15
),
SepticShockPatients AS (
  SELECT
    pp.subject_id
  FROM
    PatientProfile AS pp
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON pp.subject_id = di.subject_id
  WHERE
    di.icd_code = 'R65.21' -- Septic shock code
),
RiskScore AS (
  SELECT
    ss.subject_id,
    AVG(rs.mean_risk_score) AS mean_risk_score
  FROM
    SepticShockPatients AS ss
  JOIN
    `physionet-data.mimiciv_3_1_hosp.risk_scores` AS rs
    ON ss.subject_id = rs.subject_id
  GROUP BY
    ss.subject_id
),
Mortality AS (
  SELECT
    ss.subject_id,
    CASE
      WHEN p.dod IS NOT NULL THEN 1
      ELSE 0
    END AS mortality
  FROM
    SepticShockPatients AS ss
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ss.subject_id = p.subject_id
),
ComplicationRate AS (
  SELECT
    ss.subject_id,
    COUNT(DISTINCT c.icd_code) AS num_complications
  FROM
    SepticShockPatients AS ss
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS c
    ON ss.subject_id = c.subject_id
  WHERE
    c.icd_code IN ('I50.9', 'J81.0', 'E87.7') -- Example complication codes
  GROUP BY
    ss.subject_id
),
LOS AS (
  SELECT
    ss.subject_id,
    a.los AS survivor_los
  FROM
    SepticShockPatients AS ss
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON ss.subject_id = a.subject_id
  WHERE
    a.hospital_expire_flag = 0
  GROUP BY
    ss.subject_id
)
SELECT
  AVG(rs.mean_risk_score) AS avg_risk_score,
  AVG(m.mortality) AS mortality_rate,
  AVG(c.num_complications) AS complication_rate,
  AVG(l.survivor_los) AS survivor_los
FROM
  RiskScore AS rs
JOIN
  Mortality AS m
  ON rs.subject_id = m.subject_id
JOIN
  ComplicationRate AS c
  ON rs.subject_id = c.subject_id
JOIN
  LOS AS l
  ON rs.subject_id = l.subject_id;