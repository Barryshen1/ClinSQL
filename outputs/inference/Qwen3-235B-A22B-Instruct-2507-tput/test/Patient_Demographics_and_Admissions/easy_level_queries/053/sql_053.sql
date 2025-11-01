WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0
),

aki_admissions AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    LOWER(d.long_title) LIKE '%acute kidney injury%'
    OR d.icd_code LIKE 'N17%'
  )
),

readmission_flags AS (
  SELECT
    pa.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = pa.subject_id
          AND a2.admittime > pa.dischtime
          AND a2.admittime <= pa.dischtime + INTERVAL 30 DAY
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM patient_admissions pa
  INNER JOIN aki_admissions aki
    ON pa.hadm_id = aki.hadm_id
)

SELECT
  STDDEV(thirty_day_readmission) AS std_dev_30day_readmission
FROM readmission_flags;