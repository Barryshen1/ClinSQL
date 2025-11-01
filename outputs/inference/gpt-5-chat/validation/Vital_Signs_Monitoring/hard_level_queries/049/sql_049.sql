WITH sepsis_cohort AS (
  SELECT DISTINCT icu.subject_id,
                  icu.hadm_id,
                  icu.stay_id,
                  pat.gender,
                  pat.anchor_age,
                  adm.hospital_expire_flag,
                  icu.intime,
                  icu.outtime,
                  icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON icu.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code
   AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND (LOWER(ddx.long_title) LIKE '%sepsis%' OR LOWER(ddx.long_title) LIKE '%septicemia%')
),
score_24h AS (
  SELECT sc.subject_id,
         sc.hadm_id,
         sc.stay_id,
         sc.gender,
         sc.anchor_age,
         sc.hospital_expire_flag,
         sc.los,
         AVG(ce.valuenum) AS instability_score
  FROM sepsis_cohort sc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON sc.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) = 'instability score'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN sc.intime AND DATETIME_ADD(sc.intime, INTERVAL 24 HOUR)
  GROUP BY sc.subject_id, sc.hadm_id, sc.stay_id, sc.gender, sc.anchor_age, sc.hospital_expire_flag, sc.los
),
percentile_calc AS (
  SELECT
    100 * COUNTIF(instability_score <= 85) / NULLIF(COUNT(*), 0) AS percentile_for_85
  FROM score_24h
),
quartiles AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM score_24h
),
quartile4_stats AS (
  SELECT
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
  FROM quartiles
  WHERE quartile = 4
)
SELECT
  p.percentile_for_85,
  q.mean_icu_los,
  q.hospital_mortality_rate
FROM percentile_calc p
CROSS JOIN quartile4_stats q;