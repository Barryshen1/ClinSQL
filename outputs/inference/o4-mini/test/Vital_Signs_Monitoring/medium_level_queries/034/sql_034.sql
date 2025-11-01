WITH eligible_stays AS (
  SELECT
    icu.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON a.hadm_id = icu.hadm_id
         AND p.subject_id = icu.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_pe
          ON pe.itemid = di_pe.itemid
      WHERE
        pe.stay_id = icu.stay_id
        AND (
          LOWER(CAST(pe.value AS STRING)) LIKE '%cpap%'
          OR LOWER(CAST(pe.value AS STRING)) LIKE '%bipap%'
          OR LOWER(di_pe.label) LIKE '%cpap%'
          OR LOWER(di_pe.label) LIKE '%bipap%'
        )
    )
),

max_dbp_per_stay AS (
  SELECT
    c.stay_id,
    MAX(c.valuenum) AS max_dbp
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON es.stay_id = c.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di_ch
      ON c.itemid = di_ch.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND LOWER(di_ch.label) LIKE '%diastolic%'
    AND LOWER(di_ch.unitname) = 'mmhg'
  GROUP BY
    c.stay_id
)

SELECT
  -- 25th percentile of the per‐stay maximum diastolic BPs
  (SELECT APPROX_QUANTILES(max_dbp, 100)[OFFSET(25)]
   FROM max_dbp_per_stay) AS dbp_25th_percentile;