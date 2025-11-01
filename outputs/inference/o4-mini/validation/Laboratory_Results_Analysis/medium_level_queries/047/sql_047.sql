WITH acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code = dicd.icd_code
     AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      d.icd_code = 'I20.0'
      OR STARTS_WITH(d.icd_code, 'I21')
      OR LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
    )
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime
),
initial_tn AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    le.valuenum AS initial_tn
  FROM
    acs_admissions AS aa
    JOIN (
      SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER(
          PARTITION BY le.subject_id, le.hadm_id
          ORDER BY le.charttime
        ) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
          ON le.itemid = di.itemid
      WHERE
        le.valuenum IS NOT NULL
        AND LOWER(di.label) LIKE '%troponin t%'
    ) AS le
      ON aa.subject_id = le.subject_id
     AND aa.hadm_id    = le.hadm_id
     AND le.rn = 1
),
percentiles AS (
  SELECT
    quantiles_100[OFFSET(99)] AS p99,
    quartiles_4[OFFSET(1)]    AS q1,
    quartiles_4[OFFSET(2)]    AS median,
    quartiles_4[OFFSET(3)]    AS q3
  FROM (
    SELECT
      APPROX_QUANTILES(t.initial_tn, 100) AS quantiles_100,
      APPROX_QUANTILES(t.initial_tn, 4)   AS quartiles_4
    FROM initial_tn AS t
  )
)
SELECT
  COUNT(DISTINCT it.subject_id)   AS patient_count,
  COUNT(DISTINCT it.hadm_id)      AS admission_count,
  AVG(it.initial_tn)              AS mean_initial_tn,
  pct.median                      AS median_initial_tn,
  (pct.q3 - pct.q1)               AS iqr_initial_tn
FROM
  initial_tn AS it
  CROSS JOIN percentiles AS pct
WHERE
  it.initial_tn >= pct.p99;