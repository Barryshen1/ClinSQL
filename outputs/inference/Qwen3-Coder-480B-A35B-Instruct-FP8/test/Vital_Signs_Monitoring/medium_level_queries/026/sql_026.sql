WITH cohort AS (
  SELECT
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age,
    EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS age_at_admission
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
      ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age BETWEEN 68 AND 78
),

rr_data AS (
  SELECT
    ch.stay_id,
    AVG(ch.valuenum) AS avg_rr
  FROM
    physionet-data.mimiciv_3_1_icu.chartevents ch
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
      ON ch.itemid = di.itemid
  JOIN
    cohort co
      ON ch.stay_id = co.stay_id
  WHERE
    di.label LIKE '%Respiratory Rate%'
    AND ch.valuenum IS NOT NULL
    AND ch.valuenum > 0
    AND ch.valuenum <= 100
    AND ch.charttime >= co.intime
    AND ch.charttime <= DATETIME_ADD(co.intime, INTERVAL 48 HOUR)
  GROUP BY
    ch.stay_id
),

user_percentile AS (
  SELECT
    ROUND(100 * (
      SELECT COUNT(*) FROM rr_data WHERE avg_rr < 12
    ) / (
      SELECT COUNT(*) FROM rr_data
    ), 2) AS percentile_rank
  WHERE (SELECT COUNT(*) FROM rr_data) > 0
)

SELECT
  percentile_rank
FROM
  user_percentile;