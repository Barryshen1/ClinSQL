WITH patients_filtered AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
),

sepsis_patients AS (
  SELECT
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag,
    MAX(CASE WHEN d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE WHEN d.icd_code = 'R65.21' THEN 1 ELSE 0 END) AS has_septic_shock
  FROM
    patients_filtered pf
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    pf.hadm_id = d.hadm_id
  GROUP BY
    pf.subject_id,
    pf.hadm_id,
    pf.admittime,
    pf.dischtime,
    pf.hospital_expire_flag
  HAVING
    has_sepsis = 1 AND has_septic_shock = 0
),

comorbidities AS (
  SELECT
    sp.subject_id,
    sp.hadm_id,
    sp.admittime,
    sp.dischtime,
    sp.hospital_expire_flag,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN SUBSTR(d.icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E12', 'E13') THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN SUBSTR(d.icd_code, 1, 3) = 'I48' THEN 1 ELSE 0 END) AS has_afib,
    MAX(CASE WHEN SUBSTR(d.icd_code, 1, 3) IN ('I10', 'I11', 'I12', 'I13', 'I15') THEN 1 ELSE 0 END) AS has_hypertension
  FROM
    sepsis_patients sp
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    sp.hadm_id = d.hadm_id
  GROUP BY
    sp.subject_id,
    sp.hadm_id,
    sp.admittime,
    sp.dischtime,
    sp.hospital_expire_flag
)

SELECT
  CASE WHEN DATE_DIFF(dischtime, admittime, DAY) <= 5 THEN '≤5' ELSE '>5' END AS los_category,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM
  comorbidities
GROUP BY
  los_category,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension
ORDER BY
  los_category,
  has_ckd,
  has_diabetes,
  has_afib,
  has_hypertension;