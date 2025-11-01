WITH sepsis_patients AS (
  -- Get male patients aged 64-74 with sepsis (excluding septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    MAX(CASE WHEN d.icd_code IN ('N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.icd_code IN (
      'R65.2', 'A41.9', 'A41.8', 'A41.5', 'A41.4', 'A41.3', 'A41.2', 'A41.1', 'A41.0',
      'A40.9', 'A40.8', 'A40.3', 'A40.2', 'A40.1', 'A40.0', 'A39.9', 'A39.8', 'A39.5',
      'A39.4', 'A39.3', 'A39.2', 'A39.1', 'A39.0', 'A26.7', 'A26.0', 'A22.7', 'A22.0',
      'A21.7', 'A21.0', 'A20.7', 'A20.0', 'A19.0', 'A18.0', 'A17.9', 'A17.8', 'A17.1',
      'A17.0', 'A16.8', 'A16.5', 'A16.2', 'A16.1', 'A16.0', 'A15.0', 'A04.7', 'A04.6',
      'A04.5', 'A04.4', 'A04.3', 'A04.2', 'A04.1', 'A04.0', 'A03.9', 'A03.8', 'A03.3',
      'A03.2', 'A03.1', 'A03.0', 'A02.9', 'A02.8', 'A02.2', 'A02.1', 'A02.0', 'A01.0',
      'A00.9', 'A00.1', 'A00.0'
    )
    AND d.icd_code NOT IN ('R65.21') -- Exclude septic shock
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, los_days
),

los_quartiles AS (
  -- Calculate LOS quartiles
  SELECT
    hadm_id,
    los_days,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile,
    hospital_expire_flag,
    has_ckd,
    has_diabetes
  FROM
    sepsis_patients
)

-- Final aggregation by LOS quartile
SELECT
  los_quartile,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate,
  ROUND(SUM(has_ckd) / COUNT(*) * 100, 2) AS ckd_prevalence,
  ROUND(SUM(has_diabetes) / COUNT(*) * 100, 2) AS diabetes_prevalence
FROM
  los_quartiles
GROUP BY
  los_quartile
ORDER BY
  los_quartile;