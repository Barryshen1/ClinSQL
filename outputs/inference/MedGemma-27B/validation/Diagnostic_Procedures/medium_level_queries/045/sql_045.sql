WITH PatientInfo AS (
  SELECT
    subject_id,
    hadm_id,
    gender,
    anchor_age,
    -- Calculate LOS (Length of Stay)
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    anchor_age BETWEEN 78 AND 88
    AND gender = 'F'
), DiagnosisInfo AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'I26.99' -- DVT code
), ICUStayInfo AS (
  SELECT
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
), NoninvasiveDiagnostics AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT itemid) AS diagnostic_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE
    itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_icu.d_items`
      WHERE
        category = 'Diagnostic'
        AND label LIKE '%noninvasive%'
    )
  GROUP BY
    hadm_id
)
SELECT
  CASE
    WHEN icu.stay_id IS NOT NULL
    THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  CASE
    WHEN p.los BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN p.los BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS los_group,
  COUNT(DISTINCT p.hadm_id) AS admission_count,
  AVG(n.diagnostic_count) AS mean_diagnostics
FROM
  PatientInfo AS p
  INNER JOIN DiagnosisInfo AS di
    ON p.hadm_id = di.hadm_id
  LEFT JOIN ICUStayInfo AS icu
    ON p.hadm_id = icu.hadm_id
  LEFT JOIN NoninvasiveDiagnostics AS n
    ON p.hadm_id = n.hadm_id
WHERE
  p.subject_id IN (
    SELECT
      subject_id
    FROM
      DiagnosisInfo
  )
GROUP BY
  icu_status,
  los_group
ORDER BY
  icu_status,
  los_group;