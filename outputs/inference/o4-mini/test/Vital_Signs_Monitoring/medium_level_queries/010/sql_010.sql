WITH female_icustays AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
systolic_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%sys%'
    AND unitname = 'mmHg'
),
bp_averages AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    AVG(ce.valuenum) AS avg_systolic
  FROM
    female_icustays fs
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON fs.subject_id = ce.subject_id
     AND fs.hadm_id    = ce.hadm_id
     AND fs.stay_id    = ce.stay_id
     AND ce.charttime BETWEEN fs.intime AND TIMESTAMP_ADD(fs.intime, INTERVAL 48 HOUR)
    JOIN systolic_items si
      ON ce.itemid = si.itemid
  WHERE
    ce.valuenum IS NOT NULL
  GROUP BY
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_systolic <= 160) / COUNT(*) AS percentile_of_160
  FROM
    bp_averages
)
SELECT
  percentile_of_160
FROM
  percentile_calc;