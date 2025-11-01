WITH instability_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability%'
),
cohort_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p ON p.subject_id = i.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
        ON di.icd_code = dcd.icd_code AND di.icd_version = dcd.icd_version
      WHERE di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
        AND LOWER(dcd.long_title) LIKE '%sepsis%'
    )
),
instability_values AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id,
         MAX(te.valuenum) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS te
  JOIN instability_items AS ii ON te.itemid = ii.itemid
  JOIN cohort_stays AS s
    ON s.subject_id = te.subject_id
   AND s.hadm_id = te.hadm_id
   AND te.charttime >= s.intime
   AND te.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
),
percentile85 AS (
  SELECT 100.0 * SUM(CASE WHEN instability_score <= 85 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_85
  FROM instability_values
),
p75 AS (
  SELECT q[OFFSET(3)] AS p75
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 4) AS q
    FROM instability_values
  )
),
quartile4 AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.instability_score
  FROM instability_values i
  CROSS JOIN p75
  WHERE i.instability_score >= p75.p75
)
SELECT
  p85.percentile_85 AS percentile_of_85,
  q4_mean.mean_icu_los_hours,
  q4_mean.mean_hospital_mortality
FROM percentile85 p85
CROSS JOIN (
  SELECT AVG(icu.los) AS mean_icu_los_hours,
         AVG(ad.hospital_expire_flag) AS mean_hospital_mortality
  FROM quartile4 q
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.subject_id = q.subject_id
   AND icu.hadm_id = q.hadm_id
   AND icu.stay_id = q.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON ad.subject_id = q.subject_id
   AND ad.hadm_id = q.hadm_id
) q4_mean;