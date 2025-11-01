WITH per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
   AND icu.hadm_id = ce.hadm_id
   AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  WHERE ce.charttime BETWEEN icu.intime AND icu.outtime
    AND (LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%')
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'Female'
    AND p.anchor_age >= 42 AND p.anchor_age <= 52
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
)

SELECT
  COUNT(*) AS cohort_size,
  100.0 * SUM(CASE WHEN avg_hr <= 90 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_90
FROM per_stay;