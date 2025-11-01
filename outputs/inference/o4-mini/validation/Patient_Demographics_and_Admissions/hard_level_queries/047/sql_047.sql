WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY'
    AND d.seq_num = 1
    AND (
      STARTS_WITH(d.icd_code, 'I60')
      OR STARTS_WITH(d.icd_code, 'I61')
      OR STARTS_WITH(d.icd_code, 'I62')
    )
),
readmission_flags AS (
  SELECT
    ia.*,
    CASE
      WHEN nex.next_adm_time IS NOT NULL THEN 1
      ELSE 0
    END AS readmit
  FROM
    index_admissions ia
    LEFT JOIN (
      SELECT
        ia2.hadm_id AS idx_hadm,
        MIN(a2.admittime) AS next_adm_time
      FROM
        index_admissions ia2
        JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
          ON ia2.subject_id = a2.subject_id
          AND a2.admittime > ia2.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(ia2.dischtime, INTERVAL 30 DAY)
      GROUP BY
        ia2.hadm_id
    ) nex
    ON ia.hadm_id = nex.idx_hadm
)
SELECT
  readmit,
  COUNT(*) AS admissions_count,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_days,
  ROUND(100.0 * COUNTIF(los > 4) / COUNT(*), 1) AS pct_los_gt_4_days,
  ROUND(100.0 * AVG(readmit), 1) AS overall_readmission_rate_pct
FROM
  readmission_flags
GROUP BY
  readmit
ORDER BY
  readmit;