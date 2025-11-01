WITH cardiac_arrest_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dx.icd_code = dd.icd_code
    AND dx.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 55 AND 65
    AND (
      (dx.icd_version = 9 AND dx.icd_code = '4275')
      OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I46%')
      OR LOWER(dd.long_title) LIKE '%cardiac arrest%'
    )
),
-- Placeholder: replace with actual first-24h instability calculation
-- For demonstration, simulate scores from some table or logic
instability AS (
  SELECT
    coh.subject_id,
    coh.hadm_id,
    coh.stay_id,
    coh.hospital_expire_flag,
    coh.los,
    MOD(FARM_FINGERPRINT(CAST(coh.stay_id AS STRING)), 101) AS vs_score
    -- Replace above with actual derived instability score
  FROM cardiac_arrest_cohort coh
)
, stats AS (
  SELECT
    vs_score,
    PERCENT_RANK() OVER (ORDER BY vs_score) AS pct_rank
  FROM instability
)
, cutoff AS (
  SELECT PERCENTILE_CONT(vs_score, 0.9) OVER() AS p90_score
  FROM instability
  LIMIT 1
)
SELECT
  -- Percentile of score = 70
  (SELECT MAX(pct_rank)*100
   FROM stats
   WHERE vs_score <= 70) AS percentile_for_score_70,
  -- Metrics for top decile
  (SELECT AVG(los)
   FROM instability i, cutoff c
   WHERE i.vs_score >= c.p90_score) AS mean_los_top_decile,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64))
   FROM instability i, cutoff c
   WHERE i.vs_score >= c.p90_score) AS mortality_rate_top_decile
;