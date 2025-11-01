WITH sepsis_cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id,
         pat.gender, pat.anchor_age,
         adm.hospital_expire_flag,
         icu.intime, icu.outtime, icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id
   AND icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.subject_id = dx.subject_id
   AND icu.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
   AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND (
      (dx.icd_version = 9 AND (
         dx.icd_code LIKE '038%' OR
         dx.icd_code LIKE '99591%' OR
         dx.icd_code LIKE '99592%' OR
         dx.icd_code LIKE '78552%' /* septic shock ICD9 */
      ))
      OR
      (dx.icd_version = 10 AND (
         dx.icd_code LIKE 'A40%' OR
         dx.icd_code LIKE 'A41%'
      ))
    )
),
diag_util_per_stay AS (
  SELECT sc.stay_id,
         COUNT(DISTINCT lab.itemid) +
         COUNT(DISTINCT micro.test_itemid) AS diag_count,
         sc.hospital_expire_flag,
         sc.los
  FROM sepsis_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON sc.subject_id = lab.subject_id
   AND sc.hadm_id = lab.hadm_id
   AND lab.charttime BETWEEN sc.intime
                         AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON sc.subject_id = micro.subject_id
   AND sc.hadm_id = micro.hadm_id
   AND micro.charttime BETWEEN sc.intime
                           AND TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
  GROUP BY sc.stay_id, sc.hospital_expire_flag, sc.los
),
stats AS (
  SELECT
    STDDEV_POP(diag_count) AS diag_sd,
    APPROX_QUANTILES(diag_count, 100)[75] AS diag_p75,
    APPROX_QUANTILES(diag_count, 100)[95] AS diag_p95,
    100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END)/COUNT(*) AS mortality_percent,
    AVG(los) AS avg_icu_los_days,
    COUNT(DISTINCT stay_id) AS admissions_count
  FROM diag_util_per_stay
)
SELECT
  s.diag_sd,
  s.diag_p75,
  s.diag_p95,
  s.mortality_percent,
  s.avg_icu_los_days,
  s.admissions_count AS admissions_in_cohort,
  total_icu.total_stays AS total_icu_stays_overall
FROM stats s
CROSS JOIN (
  SELECT COUNT(*) AS total_stays
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
) total_icu;