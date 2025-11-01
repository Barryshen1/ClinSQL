WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
    AND l.valuenum > 0.04
    AND l.charttime = (
      SELECT MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2
      WHERE l2.hadm_id = l.hadm_id
        AND l2.itemid = l.itemid
    )
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr_troponin
FROM
  troponin_first t
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  t.hadm_id = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  a.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
ON
  a.hadm_id = di.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
ON
  di.icd_code = d_diag.icd_code
  AND di.icd_version = d_diag.icd_version
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 49 AND 59
  AND di.seq_num = 1
  AND (
    (d_diag.icd_version = 9 AND d_diag.icd_code LIKE '410%')
    OR
    (d_diag.icd_version = 10 AND d_diag.icd_code LIKE 'I21%')
  );