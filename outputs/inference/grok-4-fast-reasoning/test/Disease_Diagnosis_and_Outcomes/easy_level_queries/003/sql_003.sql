SELECT
  APPROX_QUANTILES(
    CAST(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS FLOAT64),
    4
  )[OFFSET(1)] AS p25_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
ON
  a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
  AND d.seq_num = 1
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 40 AND 50
  AND a.dischtime > a.admittime
  AND (
    (d.icd_version = 9
     AND LEFT(d.icd_code, 3) IN ('410', '411', '412', '413', '414'))
    OR
    (d.icd_version = 10
     AND LEFT(d.icd_code, 3) IN ('I20', 'I21', 'I22', 'I23', 'I24', 'I25'))
  );