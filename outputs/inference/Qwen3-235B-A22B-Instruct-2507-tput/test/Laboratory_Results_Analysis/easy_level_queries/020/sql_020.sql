SELECT
  APPROX_QUANTILES(min_hb, 100)[OFFSET(75)] AS hemoglobin_75th_percentile_nadir
FROM (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS min_hb
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON le.hadm_id = adm.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    LOWER(dlab.label) = 'hemoglobin'
    AND LOWER(d_diag.long_title) LIKE '%heart failure%'
    AND p.gender = 'M'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= adm.admittime
    AND le.charttime <= adm.dischtime
  GROUP BY
    le.hadm_id
) AS nadir_hb_per_admission;