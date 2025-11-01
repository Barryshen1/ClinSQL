SELECT
  APPROX_QUANTILES(avg_glucose, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(avg_glucose, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(avg_glucose, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_glucose, 100)[OFFSET(25)] AS iqr
FROM (
  SELECT
    a.hadm_id,
    AVG(l.valuenum) AS avg_glucose
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 94
    AND (dd.long_title LIKE '%ischemic%' OR dd.long_title LIKE '%cerebral infarction%')
    AND dl.label LIKE '%glucose%'
    AND dl.category = 'Chemistry'
    AND dl.fluid = 'Serum'
    AND DATE(l.charttime) = DATE(a.dischtime)
    AND l.valuenum IS NOT NULL
  GROUP BY
    a.hadm_id
);