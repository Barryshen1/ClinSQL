WITH FirstSodium AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.charttime,
    ic.valuenum AS sodium_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ic
  WHERE
    ic.itemid = 50912 -- Serum Sodium itemid
    AND ic.valuenum IS NOT NULL
),
FirstSodiumPerStay AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    MIN(fs.charttime) AS first_charttime
  FROM
    FirstSodium AS fs
  GROUP BY
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id
),
IndexSodium AS (
  SELECT
    fs.subject_id,
    fs.hadm_id,
    fs.stay_id,
    fs.sodium_value
  FROM
    FirstSodium AS fs
  INNER JOIN
    FirstSodiumPerStay AS fns
  ON
    fs.subject_id = fns.subject_id
    AND fs.hadm_id = fns.hadm_id
    AND fs.stay_id = fns.stay_id
    AND fs.charttime = fns.first_charttime
)
SELECT
  PERCENTILE_CONT(0.25, sodium_value) AS iqr_25,
  PERCENTILE_CONT(0.75, sodium_value) AS iqr_75
FROM
  IndexSodium
WHERE
  subject_id IN (
    SELECT
      subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'M'
      AND p.anchor_age = 89
  );