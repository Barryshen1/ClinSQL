WITH first_stays AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT icu.*, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  ) AS s
  WHERE rn = 1
),

trauma_hads AS (
  -- admissions with any diagnosis whose long_title contains 'trauma'
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%trauma%'
),

cohort_stays AS (
  SELECT fs.subject_id,
         fs.hadm_id,
         fs.stay_id,
         fs.intime,
         fs.outtime,
         fs.los,
         p.gender,
         p.anchor_age,
         a.hospital_expire_flag
  FROM first_stays fs
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fs.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fs.hadm_id = a.hadm_id
  JOIN trauma_hads th
    ON fs.hadm_id = th.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

vitals AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.intime,
    cs.los,
    cs.hospital_expire_flag,
    SUM(CASE
          WHEN (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%pulse%')
               AND de.valuenum IS NOT NULL
               AND de.valuenum > 100 THEN 1
          ELSE 0
        END) AS tachy_count,
    SUM(CASE
          WHEN ((LOWER(di.label) LIKE '%systolic%' AND (LOWER(di.label) LIKE '%blood pressure%' OR LOWER(di.label) LIKE '%bp%'))
                OR LOWER(di.label) LIKE '%nbp systolic%')
               AND de.valuenum IS NOT NULL
               AND de.valuenum < 90 THEN 1
          ELSE 0
        END) AS hypo_count,
    SUM(CASE
          WHEN (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%rr%')
               AND de.valuenum IS NOT NULL
               AND de.valuenum > 20 THEN 1
          ELSE 0
        END) AS tachyp_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` de
    ON de.stay_id = cs.stay_id
    AND de.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON de.itemid = di.itemid
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id, cs.intime, cs.los, cs.hospital_expire_flag
),

per_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    hospital_expire_flag,
    IFNULL(tachy_count, 0) AS tachy_count,
    IFNULL(hypo_count, 0) AS hypo_count,
    IFNULL(tachyp_count, 0) AS tachyp_count,
    (IFNULL(tachy_count, 0) + IFNULL(hypo_count, 0) + IFNULL(tachyp_count, 0)) AS instability_score
  FROM vitals
),

with_quartile AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM per_stay
),

quartile_stats AS (
  SELECT
    quartile,
    COUNT(*) AS n_stays,
    AVG(instability_score) AS mean_score,
    AVG(los) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(tachy_count) AS mean_tachy_count,
    AVG(hypo_count) AS mean_hypo_count,
    AVG(tachyp_count) AS mean_tachyp_count
  FROM with_quartile
  GROUP BY quartile
  ORDER BY quartile
),

decile_threshold AS (
  SELECT APPROX_QUANTILES(instability_score, 10)[OFFSET(9)] AS thr
  FROM per_stay
)

SELECT
  'quartile' AS group_type,
  CAST(quartile AS STRING) AS group_label,
  n_stays,
  mean_score,
  mean_icu_los,
  mortality_rate,
  mean_tachy_count,
  mean_hypo_count,
  mean_tachyp_count,
  NULL AS threshold_score
FROM quartile_stats

UNION ALL

SELECT
  'top_decile' AS group_type,
  'top_decile' AS group_label,
  COUNT(*) AS n_stays,
  AVG(instability_score) AS mean_score,
  AVG(los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(tachy_count) AS mean_tachy_count,
  AVG(hypo_count) AS mean_hypo_count,
  AVG(tachyp_count) AS mean_tachyp_count,
  (SELECT thr FROM decile_threshold) AS threshold_score
FROM per_stay
WHERE instability_score >= (SELECT thr FROM decile_threshold)
ORDER BY group_type, group_label;