WITH
  cohort_icustays AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      p.anchor_age,
      ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 68 AND 78
  ),
  first_icustays AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      anchor_age
    FROM
      cohort_icustays
    WHERE
      rn = 1
  ),
  respiratory_events AS (
    SELECT
      f.subject_id,
      f.hadm_id,
      f.stay_id,
      f.intime,
      c.valuenum AS respiratory_rate
    FROM
      first_icustays f
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON f.subject_id = c.subject_id
      AND f.hadm_id = c.hadm_id
      AND f.stay_id = c.stay_id
    WHERE
      c.itemid = 220045
      AND c.charttime BETWEEN f.intime AND f.intime + INTERVAL 48 HOUR
  ),
  cohort_avg AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      AVG(respiratory_rate) AS avg_respiratory_rate
    FROM
      respiratory_events
    GROUP BY
      subject_id, hadm_id, stay_id
    HAVING
      COUNT(respiratory_rate) > 0
  ),
  percentile_calc AS (
    SELECT
      (COUNTIF(avg_respiratory_rate <= 12) * 100.0) / COUNT(*) AS percentile
    FROM
      cohort_avg
  )
SELECT
  percentile
FROM
  percentile_calc;