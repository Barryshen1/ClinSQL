WITH
  -- 1) Identify ICU stays for the target group: female, age 56-66, with ICH
  ich_cohort AS (
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.intime,
      ic.outtime,
      ic.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON ic.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 56 AND 66
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE dx.subject_id = ic.subject_id
          AND dx.hadm_id = ic.hadm_id
          AND (
            (dx.icd_version = 9 AND dx.icd_code = '431')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I61%')
          )
      )
  ),

  -- 2) Diagnostic intensity: count labevents in first 72 hours of ICU stay
  intensity72h AS (
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      COUNT(le.labevent_id) AS intensity_72h
    FROM ich_cohort AS ic
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON le.subject_id = ic.subject_id
     AND le.hadm_id = ic.hadm_id
     AND le.charttime >= ic.intime
     AND le.charttime < TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY ic.subject_id, ic.hadm_id, ic.stay_id
  ),

  -- 3) 95th percentile of diagnostic intensity in this cohort
  intensity_95 AS (
    SELECT (APPROX_QUANTILES(intensity_72h, 100)[OFFSET(95)]) AS intensity_95
    FROM intensity72h
  ),

  -- 4) ICU subgroup and LOS/mortality metrics for comparison
  group_los_mort AS (
    SELECT
      (APPROX_QUANTILES(ic.los, 100)[OFFSET(50)]) AS los_median_group,
      AVG(CASE WHEN adm.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mort_rate_group
    FROM ich_cohort ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON ic.hadm_id = adm.hadm_id
  ),

  -- 5) ICU population for comparison
  icu_population AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- 6) ICU population: median LOS
  icu_los_mort AS (
    SELECT (APPROX_QUANTILES(ic.los, 100)[OFFSET(50)]) AS los_median_icu
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN icu_population ip ON ic.hadm_id = ip.hadm_id
  ),

  -- 7) ICU population mortality
  icu_mort AS (
    SELECT AVG(CASE WHEN adm.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS mort_rate_icu
    FROM icu_population ip
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON ip.hadm_id = adm.hadm_id
  )

SELECT
  intensity_95.intensity_95 AS intensity_95_72h,
  group_los_mort.los_median_group,
  group_los_mort.mort_rate_group,
  icu_los_mort.los_median_icu,
  icu_mort.mort_rate_icu
FROM intensity_95
CROSS JOIN group_los_mort
CROSS JOIN icu_los_mort
CROSS JOIN icu_mort;