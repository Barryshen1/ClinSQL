WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) BETWEEN 84 AND 94
),

echocardiography_procedures AS (
  SELECT
    pa.subject_id,
    h.hcpcs_cd
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  ON
    pa.hadm_id = h.hadm_id
  WHERE
    h.hcpcs_cd BETWEEN '93303' AND '93356'
)

SELECT
  MAX(procedure_count) AS max_distinct_echo_procedures
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT hcpcs_cd) AS procedure_count
  FROM
    echocardiography_procedures
  GROUP BY
    subject_id
);