WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON adm.subject_id = d.subject_id
      AND adm.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND adm.admission_type = 'EMERGENCY'
    AND adm.insurance LIKE '%MEDICARE%'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute pancreatitis%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
indexed AS (
  SELECT
    c.*,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime   > c.dischtime
        AND a2.admittime   <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS readmitted
  FROM cohort AS c
)
SELECT
  readmitted,
  COUNT(*) AS num_stays,
  ROUND(
    100.0 * COUNTIF(readmitted) / SUM(COUNT(*)) OVER (),
    2
  ) AS pct_readmission_overall,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  ROUND(
    100.0 * COUNTIF(los > 9) / COUNT(*),
    2
  ) AS pct_los_over_9_days
FROM indexed
GROUP BY readmitted
ORDER BY readmitted DESC;