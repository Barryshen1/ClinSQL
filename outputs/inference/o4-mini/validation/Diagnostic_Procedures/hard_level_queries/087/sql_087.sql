WITH cohort_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS died,
    (
      SELECT
        COUNT(*) 
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE
        le.subject_id = icu.subject_id
        AND le.hadm_id    = icu.hadm_id
        AND le.charttime BETWEEN icu.intime
                             AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    ) AS intensity
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      USING(subject_id)
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code    = dd.icd_code
         AND d.icd_version = dd.icd_version
      WHERE
        d.subject_id = icu.subject_id
        AND d.hadm_id    = icu.hadm_id
        AND LOWER(dd.long_title) LIKE '%intracranial hemorrhage%'
    )
),
overall_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    CASE WHEN adm.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS died,
    (
      SELECT
        COUNT(*) 
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE
        le.subject_id = icu.subject_id
        AND le.hadm_id    = icu.hadm_id
        AND le.charttime BETWEEN icu.intime
                             AND DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    ) AS intensity
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      USING(subject_id, hadm_id)
)

SELECT
  'ICH cohort (F, age 56–66)' AS cohort,
  APPROX_QUANTILES(intensity, 100)[OFFSET(95)] AS p95_intensity,
  AVG(los) AS avg_icu_los_days,
  SAFE_DIVIDE(SUM(died), COUNT(*)) AS in_hospital_mortality_rate
FROM
  cohort_stays

UNION ALL

SELECT
  'Overall ICU population' AS cohort,
  APPROX_QUANTILES(intensity, 100)[OFFSET(95)] AS p95_intensity,
  AVG(los) AS avg_icu_los_days,
  SAFE_DIVIDE(SUM(died), COUNT(*)) AS in_hospital_mortality_rate
FROM
  overall_stays;