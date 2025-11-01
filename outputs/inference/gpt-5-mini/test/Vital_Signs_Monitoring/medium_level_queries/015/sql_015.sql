WITH systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

eligible_stays AS (
  SELECT i.subject_id,
         i.hadm_id,
         i.stay_id,
         i.intime,
         i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.edregtime IS NOT NULL
),

stay_max_sbp AS (
  SELECT es.stay_id,
         MAX(c.valuenum) AS max_sbp
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = es.stay_id
  JOIN systolic_items s
    ON c.itemid = s.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 20 AND 300
    AND c.charttime BETWEEN es.intime AND es.outtime
  GROUP BY es.stay_id
)

SELECT
  APPROX_QUANTILES(max_sbp, 100)[OFFSET(75)] AS sbp_75th_percentile,
  COUNT(*) AS n_stays_used
FROM stay_max_sbp
WHERE max_sbp IS NOT NULL;