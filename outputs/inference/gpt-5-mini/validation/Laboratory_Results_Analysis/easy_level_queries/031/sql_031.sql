WITH potassium_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  USING (itemid)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  USING (subject_id, hadm_id)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(a.dischtime)
    AND LOWER(d.label) LIKE '%potassium%'
    -- exclude obvious urine potassium assays
    AND (d.fluid IS NULL OR LOWER(d.fluid) NOT LIKE '%urine%')
    -- ensure this admission included at least one ICU stay (avoid duplicate rows by using EXISTS)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.hadm_id = a.hadm_id
    )
)
SELECT
  COUNT(*) AS n_measurements,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  COUNT(DISTINCT subject_id) AS n_patients,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS potassium_75th
FROM
  potassium_labs;