WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND a.dischtime IS NOT NULL
    AND d.icd_version = 10
    AND d.seq_num = 1
    AND d.icd_code BETWEEN 'I20' AND 'I25'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 40 AND 50
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS p25_los
FROM
  filtered_admissions;