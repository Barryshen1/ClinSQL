WITH diastolic_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic blood pressure%'
),
eligible_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(s.first_careunit) LIKE '%step%'
      OR LOWER(s.first_careunit) LIKE '%imc%'
    )
),
stay_mean_dbp AS (
  SELECT
    e.stay_id,
    AVG(c.valuenum) AS mean_dbp
  FROM eligible_stays e
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.subject_id = e.subject_id
   AND c.hadm_id    = e.hadm_id
   AND c.stay_id    = e.stay_id
  JOIN diastolic_itemids d
    ON c.itemid = d.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime BETWEEN 
        (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays`
         WHERE stay_id = e.stay_id)
     AND 
        (SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays`
         WHERE stay_id = e.stay_id)
  GROUP BY e.stay_id
)
SELECT
  APPROX_QUANTILES(mean_dbp, 100)[SAFE_OFFSET(25)] AS dbp_25th_percentile,
  APPROX_QUANTILES(mean_dbp, 100)[SAFE_OFFSET(75)] AS dbp_75th_percentile
FROM stay_mean_dbp;