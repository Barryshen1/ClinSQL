SELECT
  PERCENTILE_CONT(los, 0.25) OVER() AS los_25th_percentile_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.seq_num = 1
    AND (
      -- ICD-9 codes for IHD/ACS
      (d.icd_version = 9 AND (
        LEFT(d.icd_code, 3) IN ('410', '411', '412', '413', '414')
      ))
      -- ICD-10 codes for IHD/ACS
      OR (d.icd_version = 10 AND (
        LEFT(d.icd_code, 3) IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25')
      ))
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
);