WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Placeholder: replace with actual risk score calculation
    0 AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND REGEXP_CONTAINS(LOWER(dd.long_title), 'intracranial hemorrhage')
),
with_quartiles AS (
  SELECT
    c.*,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    cohort c
),
complications AS (
  SELECT
    wq.subject_id,
    wq.hadm_id,
    wq.admittime,
    wq.dischtime,
    wq.hospital_expire_flag,
    wq.risk_score,
    wq.risk_quartile,
    MAX(CASE 
          WHEN REGEXP_CONTAINS(LOWER(dd2.long_title), 'cardiac')
          THEN 1 ELSE 0 
        END) OVER (PARTITION BY wq.subject_id, wq.hadm_id) AS cardiac_flag,
    MAX(CASE 
          WHEN REGEXP_CONTAINS(LOWER(dd2.long_title), 'neurologic')
          THEN 1 ELSE 0 
        END) OVER (PARTITION BY wq.subject_id, wq.hadm_id) AS neuro_flag
  FROM
    with_quartiles wq
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      ON wq.subject_id = d2.subject_id
      AND wq.hadm_id = d2.hadm_id
      AND d2.seq_num > 1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
      ON d2.icd_code = dd2.icd_code
      AND d2.icd_version = dd2.icd_version
),
final AS (
  SELECT
    risk_quartile,
    COUNT(DISTINCT subject_id, hadm_id) AS patient_count,
    ROUND(100 * AVG(hospital_expire_flag), 1) AS pct_in_hosp_mortality,
    ROUND(100 * AVG(cardiac_flag), 1)    AS pct_cardiac_complication,
    ROUND(100 * AVG(neuro_flag), 1)     AS pct_neuro_complication,
    -- Median LOS among survivors
    (
      SELECT
        quantiles[OFFSET(1)]
      FROM
        UNNEST(
          APPROX_QUANTILES(
            TIMESTAMP_DIFF(dischtime, admittime, DAY),
            2
          )
        ) AS quantiles
    ) AS median_los_survivors_days
  FROM
    complications
  WHERE
    hospital_expire_flag = 0
  GROUP BY
    risk_quartile
)
SELECT
  *
FROM
  final
ORDER BY
  risk_quartile;