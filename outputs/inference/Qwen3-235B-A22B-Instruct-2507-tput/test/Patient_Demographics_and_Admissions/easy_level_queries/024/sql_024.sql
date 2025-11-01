WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
aged_patients AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    gender,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM
    first_admissions
  WHERE
    rn = 1
    AND gender = 'F'
),
cabg_procedures AS (
  SELECT DISTINCT
    pi.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    pi.icd_code = d.icd_code
    AND pi.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%coronary artery bypass%'
    OR LOWER(d.long_title) LIKE '%bypass graft%coronary%'
)
SELECT
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  aged_patients ap
JOIN
  cabg_procedures cp
ON
  ap.hadm_id = cp.hadm_id
WHERE
  ap.age_at_admission BETWEEN 35 AND 45;