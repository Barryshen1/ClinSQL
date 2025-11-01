WITH male_elderly AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
spo2_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%oxygen saturation%'
    OR LOWER(label) LIKE '%spo2%'
),
first_spo2 AS (
  SELECT
    me.subject_id,
    me.hadm_id,
    me.stay_id,
    me.valuenum AS spo2_first
  FROM (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum,
      ROW_NUMBER() OVER (
        PARTITION BY ce.subject_id, ce.hadm_id, ce.stay_id
        ORDER BY ce.charttime
      ) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN spo2_items di
        ON ce.itemid = di.itemid
      JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ce.subject_id = icu.subject_id
        AND ce.hadm_id = icu.hadm_id
        AND ce.stay_id = icu.stay_id
    WHERE
      ce.charttime >= icu.intime
      AND ce.valuenum IS NOT NULL
  ) me
  WHERE
    me.rn = 1
)
SELECT
  STDDEV_SAMP(fs.spo2_first) AS sd_spo2_first
FROM
  first_spo2 fs
  JOIN male_elderly me
    ON fs.subject_id = me.subject_id
    AND fs.hadm_id = me.hadm_id;