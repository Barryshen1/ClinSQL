WITH female_elderly_adm AS (
  -- Female patients age 82-92 with chest pain or AMI
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND (
      LOWER(dd.long_title) LIKE '%chest pain%'
      OR LOWER(dd.long_title) LIKE '%myocardial infarction%'
    )
  GROUP BY
    a.subject_id,
    a.hadm_id
),
initial_troponin AS (
  -- First troponin-T per admission
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value
  FROM (
    SELECT
      le.subject_id,
      le.hadm_id,
      le.charttime,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.labevents` le
      JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
        ON le.itemid = di.itemid
    WHERE
      LOWER(di.label) LIKE '%troponin t%'
      AND SAFE_CAST(le.valuenum AS NUMERIC) IS NOT NULL
  ) le
  WHERE
    rn = 1
    AND valuenum > 0.01
)
SELECT
  quantiles[OFFSET(25)]  AS p25,
  quantiles[OFFSET(50)]  AS p50,
  quantiles[OFFSET(75)]  AS p75,
  quantiles[OFFSET(0)]   AS min_value,
  quantiles[OFFSET(100)] AS max_value
FROM (
  SELECT
    APPROX_QUANTILES(troponin_value, 100) AS quantiles
  FROM
    initial_troponin t
    JOIN female_elderly_adm f
      USING (subject_id, hadm_id)
);