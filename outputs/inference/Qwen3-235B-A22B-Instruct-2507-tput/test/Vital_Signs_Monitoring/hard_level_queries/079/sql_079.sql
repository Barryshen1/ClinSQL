WITH hfnc_cohort AS (
  SELECT DISTINCT
    pat.subject_id,
    stay.hadm_id,
    stay.stay_id,
    stay.intime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays stay
    ON pat.subject_id = stay.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
),
hfnc_use AS (
  SELECT DISTINCT
    hfnc_cohort.stay_id
  FROM hfnc_cohort
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.inputevents inp
    ON hfnc_cohort.stay_id = inp.stay_id
  WHERE inp.itemid = 228347  -- High Flow Oxygen / HFNC
    AND inp.starttime >= hfnc_cohort.intime
    AND inp.starttime <= DATETIME_ADD(hfnc_cohort.intime, INTERVAL 48 HOUR)
),
-- Placeholder for instability scores; in practice, this would be derived from chartevents, vitals, labs, etc.
instability_scores AS (
  SELECT stay_id, instability_score
  FROM `your_project.your_dataset.instability_scores`
  WHERE stay_id IN (SELECT stay_id FROM hfnc_use)
),
cohort_scores AS (
  SELECT
    s.stay_id,
    s.instability_score,
    stay.los AS icu_los,
    adm.hospital_expire_flag
  FROM instability_scores s
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays stay
    ON s.stay_id = stay.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON stay.hadm_id = adm.hadm_id
),
percentile_of_85 AS (
  SELECT
    SUM(CASE WHEN instability_score <= 85 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS percentile_rank_of_85
  FROM cohort_scores
),
ninetyth_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(900)] AS p90_score
  FROM cohort_scores
),
top_decile AS (
  SELECT
    cs.icu_los,
    cs.hospital_expire_flag
  FROM cohort_scores cs
  CROSS JOIN ninetyth_percentile
  WHERE cs.instability_score >= p90_score
)
SELECT
  -- Percentile of score 85
  (SELECT percentile_rank_of_85 FROM percentile_of_85) AS score_85_percentile,
  -- Average ICU LOS for top decile
  AVG(top.icu_los) AS avg_icu_los_top_decile,
  -- Hospital mortality (%) for top decile
  AVG(top.hospital_expire_flag) * 100 AS hospital_mortality_pct_top_decile
FROM top_decile top;