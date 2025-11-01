WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU_day1' ELSE 'No_ICU_day1' END AS icu_day1_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
    AND icu.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('785.5', '785.51', '785.59', '995.92', '518.81', '518.82', '518.85'))
          OR
          (d.icd_version = 10 AND d.icd_code IN ('R57.0', 'R57.8', 'R57.9', 'I95.9', 'J96.0', 'J96.01', 'J96.02', 'J96.9', 'J96.90', 'J96.91', 'J96.92'))
        )
    )
),
grouped AS (
  SELECT
    icu_day1_status,
    CASE WHEN los_days <= 5 THEN 'LOS <=5' ELSE 'LOS >5' END AS los_group,
    hospital_expire_flag,
    los_days
  FROM cohort
)
SELECT
  icu_day1_status,
  los_group,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
FROM grouped
GROUP BY icu_day1_status, los_group
ORDER BY icu_day1_status, los_group;