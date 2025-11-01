WITH sepsis_adms AS (
  -- Identify male patients age 50-60 with sepsis (no septic shock)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(dd.long_title) LIKE '%sepsis%'
    AND LOWER(dd.long_title) NOT LIKE '%septic shock%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
),

adms_with_icu AS (
  -- Annotate whether the patient went to ICU on day 1
  SELECT
    s.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.subject_id = s.subject_id
          AND icu.hadm_id    = s.hadm_id
          -- ICU intime within 1 day of admission
          AND icu.intime BETWEEN s.admittime
                             AND TIMESTAMP_ADD(s.admittime, INTERVAL 1 DAY)
      )
      THEN 'ICU Day1'
      ELSE 'No ICU Day1'
    END AS icu_day1_status,
    CASE
      WHEN los_days <= 7 THEN '<=7 days'
      ELSE '>7 days'
    END AS los_group
  FROM sepsis_adms s
)

SELECT
  los_group,
  icu_day1_status,
  COUNT(1)                                           AS admissions,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(1), 2) AS mortality_pct,
  -- Approximate median LOS
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)]            AS median_los_days
FROM
  adms_with_icu
GROUP BY
  los_group,
  icu_day1_status
ORDER BY
  los_group,
  icu_day1_status;