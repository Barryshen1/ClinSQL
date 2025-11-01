WITH
-- 1. Identify MAP and HR itemids
vitals AS (
  SELECT
    itemid,
    LOWER(label) AS lower_label
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
    OR LOWER(label) LIKE '%heart rate%'
),
map_itemids AS (
  SELECT itemid FROM vitals WHERE lower_label LIKE '%mean arterial pressure%'
),
hr_itemids AS (
  SELECT itemid FROM vitals WHERE lower_label LIKE '%heart rate%'
),

-- 2. Base ICU stays filtered to male, age 82–92
icu_base AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag AS mortality
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- 3. Identify ARF admissions
arf_adm AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
      ON d.icd_code = ddesc.icd_code
     AND d.icd_version = ddesc.icd_version
  WHERE
    LOWER(ddesc.long_title) LIKE '%acute respiratory failure%'
),

-- 4. Compute composite burden within first 72 hours
burdens AS (
  SELECT
    cb.subject_id,
    cb.hadm_id,
    cb.stay_id,
    cb.los,
    cb.mortality,
    COALESCE(map_counts.map_low, 0) + COALESCE(hr_counts.hr_high, 0) AS composite_burden
  FROM
    icu_base cb
  LEFT JOIN (
    SELECT
      ce.stay_id,
      COUNT(*) AS map_low
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN icu_base ib
        ON ce.stay_id = ib.stay_id
    WHERE
      ce.itemid IN (SELECT itemid FROM map_itemids)
      AND ce.valuenum < 65
      AND ce.charttime <= TIMESTAMP_ADD(ib.intime, INTERVAL 72 HOUR)
    GROUP BY
      ce.stay_id
  ) map_counts
    ON cb.stay_id = map_counts.stay_id
  LEFT JOIN (
    SELECT
      ce.stay_id,
      COUNT(*) AS hr_high
    FROM
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
      JOIN icu_base ib
        ON ce.stay_id = ib.stay_id
    WHERE
      ce.itemid IN (SELECT itemid FROM hr_itemids)
      AND ce.valuenum > 100
      AND ce.charttime <= TIMESTAMP_ADD(ib.intime, INTERVAL 72 HOUR)
    GROUP BY
      ce.stay_id
  ) hr_counts
    ON cb.stay_id = hr_counts.stay_id
),

-- 5. Tag stays as ARF vs General ICU
cohorts AS (
  SELECT
    b.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM arf_adm a
        WHERE a.subject_id = b.subject_id
          AND a.hadm_id = b.hadm_id
      ) THEN 'ARF'
      ELSE 'General_ICU'
    END AS cohort
  FROM
    burdens b
),

-- 6. Compute quantiles per cohort
quant AS (
  SELECT
    cohort,
    APPROX_QUANTILES(composite_burden, 4) AS quantiles
  FROM
    cohorts
  GROUP BY
    cohort
)

-- 7. Final aggregation
SELECT
  c.cohort,
  q.quantiles[OFFSET(1)] AS p25_burden,
  q.quantiles[OFFSET(2)] AS median_burden,
  q.quantiles[OFFSET(3)] AS p75_burden,
  q.quantiles[OFFSET(3)] - q.quantiles[OFFSET(1)] AS iqr_burden,
  AVG(c.composite_burden) AS avg_burden,
  AVG(c.los) AS avg_icu_los,
  AVG(c.mortality) AS avg_mortality
FROM
  cohorts c
JOIN
  quant q
USING(cohort)
GROUP BY
  c.cohort,
  q.quantiles
ORDER BY
  c.cohort;