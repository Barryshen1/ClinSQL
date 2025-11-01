WITH systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE 'systolic blood pressure%'
),
female_elderly_icu AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
),
bp_first48 AS (
  SELECT
    fe.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM female_elderly_icu fe
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fe.stay_id = ce.stay_id
   AND ce.valuenum IS NOT NULL
   AND ce.valuenum > 0
   AND ce.charttime >= fe.intime
   AND ce.charttime <= TIMESTAMP_ADD(fe.intime, INTERVAL 48 HOUR)
  JOIN systolic_items si
    ON ce.itemid = si.itemid
  GROUP BY fe.stay_id
)
SELECT
  100.0 * SUM(CASE WHEN avg_sbp <= 160 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_160_sbp
FROM bp_first48;