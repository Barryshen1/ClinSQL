WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.charttime = (
      SELECT MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` l2
      WHERE l2.hadm_id = l.hadm_id
        AND l2.itemid = l.itemid
    )
    AND l.valuenum > l.ref_range_upper
)

SELECT
  COUNT(DISTINCT p.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(t.troponin_value) AS mean_troponin,
  APPROX_QUANTILES(t.troponin_value, 2)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(t.troponin_value, 4)[OFFSET(1)] AS q1_troponin,
  APPROX_QUANTILES(t.troponin_value, 4)[OFFSET(3)] AS q3_troponin,
  APPROX_QUANTILES(t.troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(t.troponin_value, 4)[OFFSET(1)] AS iqr_troponin
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON a.hadm_id = dx.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
  ON dx.icd_code = d_diag.icd_code AND dx.icd_version = d_diag.icd_version
JOIN
  troponin_first t
  ON a.hadm_id = t.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 67 AND 77
  AND (
    d_diag.icd_code LIKE 'I20%'
    OR d_diag.icd_code LIKE 'I21%'
    OR d_diag.icd_code LIKE 'I22%'
    OR d_diag.icd_code LIKE 'I23%'
    OR d_diag.icd_code LIKE 'I24%'
    OR d_diag.icd_code LIKE 'I25%'
  );