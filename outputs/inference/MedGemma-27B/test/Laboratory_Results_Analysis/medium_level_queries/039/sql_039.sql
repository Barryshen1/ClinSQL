WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 87 AND 97
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE
    icd.long_title LIKE '%chest pain%'
), LabInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS hs_tnt_value,
    l.valueuom AS hs_tnt_uom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    d.label = 'Troponin I, high-sensitivity'
), TnT_Categories AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    hs_tnt_value,
    hs_tnt_uom,
    CASE
      WHEN hs_tnt_value <= 0.04 THEN 'Normal≤0.04'
      WHEN hs_tnt_value > 0.04 AND hs_tnt_value <= 0.1 THEN 'Borderline 0.04–0.1'
      WHEN hs_tnt_value > 0.1 THEN 'Injury>0.1'
      ELSE 'Other'
    END AS hs_tnt_category
  FROM LabInfo
  WHERE
    hs_tnt_uom = 'ng/L'
)
SELECT
  hs_tnt_category,
  COUNT(subject_id) AS count,
  COUNT(subject_id) * 100.0 / SUM(COUNT(subject_id)) OVER () AS percentage,
  AVG(hs_tnt_value) AS mean,
  APPROX_QUANTILES(hs_tnt_value, 4)[OFFSET(1)] AS median,
  APPROX_QUANTILES(hs_tnt_value, 4)[OFFSET(0)] AS iqr_25,
  APPROX_QUANTILES(hs_tnt_value, 4)[OFFSET(2)] AS iqr_75
FROM TnT_Categories
WHERE
  hadm_id IN (
    SELECT
      hadm_id
    FROM AdmissionInfo
    WHERE
      hadm_id IN (
        SELECT
          hadm_id
        FROM DiagnosisInfo
      )
  )
GROUP BY
  hs_tnt_category
ORDER BY
  hs_tnt_category;