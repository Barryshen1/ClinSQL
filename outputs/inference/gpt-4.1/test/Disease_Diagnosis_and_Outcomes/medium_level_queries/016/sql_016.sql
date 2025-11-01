WITH ami_admissions AS (
  -- Get admissions for males age 40-50 with AMI, excluding shock/resp failure
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
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 AMI: I21*, I22*; ICD-9 AMI: 410*
          (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
          OR
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE
        d2.hadm_id = a.hadm_id
        AND (
          -- ICD-10 shock: R57*; ICD-9 shock: 785.5*
          (d2.icd_version = 10 AND d2.icd_code LIKE 'R57%')
          OR
          (d2.icd_version = 9 AND d2.icd_code LIKE '7855%')
          -- ICD-10 resp failure: J96*; ICD-9 resp failure: 518.81, 518.84
          OR
          (d2.icd_version = 10 AND d2.icd_code LIKE 'J96%')
          OR
          (d2.icd_version = 9 AND (d2.icd_code = '51881' OR d2.icd_code = '51884'))
        )
    )
),
los_calc AS (
  -- Calculate LOS in days
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS FLOAT64) AS los_days
  FROM ami_admissions
),
icu_day1 AS (
  -- For each admission, flag if ICU stay overlaps with first 24h
  SELECT
    l.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE
          icu.hadm_id = l.hadm_id
          AND icu.intime < TIMESTAMP_ADD(l.admittime, INTERVAL 1 DAY)
          AND icu.outtime > l.admittime
      ) THEN 1
      ELSE 0
    END AS icu_day1
  FROM los_calc l
),
final AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.los_days,
    l.hospital_expire_flag,
    CASE WHEN l.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group,
    i.icu_day1
  FROM los_calc l
  JOIN icu_day1 i ON l.hadm_id = i.hadm_id
)
SELECT
  los_group,
  icu_day1,
  COUNT(*) AS n_admissions,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los
FROM final
GROUP BY los_group, icu_day1
ORDER BY los_group, icu_day1;