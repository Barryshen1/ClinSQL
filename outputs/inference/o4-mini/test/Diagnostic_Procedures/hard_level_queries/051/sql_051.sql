WITH sepsis_stays AS (
  -- ICU stays for male patients age 90–100 with any sepsis diagnosis in the same hospital admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON icu.subject_id = dx.subject_id
     AND icu.hadm_id    = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dxd
      ON dx.icd_code    = dxd.icd_code
     AND dx.icd_version = dxd.icd_version
  WHERE
    p.anchor_age BETWEEN 90 AND 100
    AND p.gender = 'M'
    AND LOWER(dxd.long_title) LIKE '%sepsis%'
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
),

lab_counts AS (
  -- Count lab events in the first 24h of each qualifying ICU stay
  SELECT
    s.stay_id,
    COUNT(le.labevent_id) AS labs_first_24h,
    s.los,
    s.hospital_expire_flag
  FROM
    sepsis_stays AS s
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON s.subject_id = le.subject_id
     AND s.hadm_id    = le.hadm_id
     AND le.charttime BETWEEN s.intime
                         AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY
    s.stay_id,
    s.los,
    s.hospital_expire_flag
),

overall_counts AS (
  -- Total number of ICU stays (for ratio calculation)
  SELECT COUNT(*) AS total_icu_stays
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)

SELECT
  -- Diagnostic utilization metrics
  STDDEV_SAMP(labs_first_24h)                                    AS lab_count_stddev,
  -- 75th and 95th percentiles via approx_quantiles
  (APPROX_QUANTILES(labs_first_24h, 100))[OFFSET(75)]            AS lab_count_p75,
  (APPROX_QUANTILES(labs_first_24h, 100))[OFFSET(95)]            AS lab_count_p95,
  -- In-hospital mortality (%)
  100.0 * SUM(IF(hospital_expire_flag = 1, 1, 0)) / COUNT(*)      AS in_hospital_mortality_pct,
  -- Average ICU length-of-stay
  AVG(los)                                                      AS avg_icu_los,
  -- Proportion of ICU stays that meet criteria vs. all ICU stays
  COUNT(*) / (SELECT total_icu_stays FROM overall_counts)       AS sepsis_icu_stay_fraction
FROM
  lab_counts;