WITH base_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- Flag AKI based on ICD diagnosis codes
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id    = a.hadm_id
          AND LOWER(dd.long_title) LIKE '%acute kidney injury%'
      ) THEN 1
      ELSE 0
    END AS is_aki
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
),

lab_stats AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    -- standard deviation of all numeric lab values in first 72h
    STDDEV(le.valuenum) AS lab_instability
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN base_adm b
      ON le.subject_id = b.subject_id
     AND le.hadm_id    = b.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN b.admittime 
                        AND TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
  GROUP BY
    le.subject_id,
    le.hadm_id
),

icu_flag AS (
  SELECT
    DISTINCT subject_id,
    hadm_id,
    1 AS had_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

per_admission AS (
  SELECT
    b.hadm_id,
    b.is_aki,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    ls.lab_instability,
    COALESCE(i.had_icu, 0) AS had_icu,
    -- LOS in days (including fractional day)
    TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY)
      + MOD(TIMESTAMP_DIFF(b.dischtime, b.admittime, HOUR), 24) / 24.0
      AS los_days
  FROM
    base_adm b
    LEFT JOIN lab_stats ls
      ON b.subject_id = ls.subject_id
     AND b.hadm_id    = ls.hadm_id
    LEFT JOIN icu_flag i
      ON b.subject_id = i.subject_id
     AND b.hadm_id    = i.hadm_id
)

SELECT
  is_aki,
  COUNT(*)                              AS n_admissions,
  ROUND(AVG(lab_instability), 3)       AS mean_lab_instability_72h,
  ROUND(AVG(had_icu) * 100, 1)          AS critical_event_pct,
  ROUND(AVG(los_days), 2)               AS avg_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 1) AS mortality_pct
FROM
  per_admission
GROUP BY
  is_aki
ORDER BY
  is_aki DESC;