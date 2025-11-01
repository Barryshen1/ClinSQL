WITH hfnc_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%high flow nasal cannula%' OR LOWER(label) LIKE '%hfnc%'
),
cohort AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN hfnc_items
    ON ce.itemid = hfnc_items.itemid
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
),
ranked_cohort AS (
  SELECT *,
    PERCENT_RANK() OVER (ORDER BY 85) AS percentile_score,
    NTILE(10) OVER (ORDER BY 85 DESC) AS decile
  FROM cohort
)
SELECT
  MAX(percentile_score) * 100 AS score_percentile,
  AVG(icu_los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM ranked_cohort
WHERE decile = 1;