WITH systolic_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%systolic%'
    AND LOWER(unitname) = 'mmhg'
),

eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

stay_avg_bp AS (
  SELECT
    es.stay_id,
    AVG(ce.valuenum) AS avg_systolic_bp
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = es.subject_id
      AND ce.hadm_id = es.hadm_id
      AND ce.stay_id = es.stay_id
    JOIN systolic_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN es.intime
                        AND TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY
    es.stay_id
  HAVING
    COUNT(*) > 0
)

SELECT
  100.0 * SUM(CASE WHEN avg_systolic_bp <= 150 THEN 1 ELSE 0 END)
    / COUNT(*) AS percentile_of_150_mmHg
FROM
  stay_avg_bp;